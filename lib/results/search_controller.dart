import 'package:flutter/foundation.dart';

import '../advanced/advanced_controller.dart';
import '../advanced/explainer.dart';
import '../advanced/gemma_runtime.dart';
import '../advanced/transfer_drafter.dart';
import '../core/transaction.dart';
import '../data/db/transaction_repository.dart';
import '../perf/stage_timer.dart';
import '../search/plan_validator.dart';
import '../search/rules/rule_refiner.dart';
import '../search/search_plan.dart';
import '../search/standard_interpreter.dart';
import 'result_pager.dart';
import 'result_summary.dart';
import 'search_engine.dart';

/// State behind the search screen. Every search gets a generation number;
/// results from an older generation are dropped (Review Focus 1).
class TransactionSearchController extends ChangeNotifier {
  TransactionSearchController({
    required this.repo,
    required this.engine,
    required this.validator,
    this.interpreter,
    this.refiner,
    this.onTiming,
    this.onMemoChanged,
    this.advanced,
    this.useAdvancedPlanner = false,
  }) {
    advanced?.addListener(_advancedChanged);
  }

  final AdvancedController? advanced;

  /// Whether [submit] and [refine] block on Gemma's pre-search query planner.
  /// Defaults to `false` so the transaction list always updates immediately via
  /// deterministic rules + SQLite + RAG, and Gemma is only used *after* the
  /// list is retrieved (for [explain] and [draftTransfer]).
  final bool useAdvancedPlanner;
  bool _planningAdvanced = false;

  void _advancedChanged() {
    if (advanced?.isOn ?? false) return;
    var changed = false;
    if (_planningAdvanced) {
      ++_generation;
      _planningAdvanced = false;
      _busy = false;
      changed = true;
    }
    // Off hides any explanation or transfer draft at once and forgets in-flight
    // work, even if the switch is turned back on before the native job finishes.
    if (_explaining ||
        _explanation != null ||
        _draftingTransfer ||
        _transferDraft != null) {
      _invalidateExplanation();
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Drops the explanation and transfer draft and makes any in-flight work
  /// land nowhere. The state change is immediate; the caller notifies.
  void _invalidateExplanation() {
    ++_explainGeneration;
    ++_draftGeneration;
    _explanation = null;
    _transferDraft = null;
    if (_explaining || _draftingTransfer) {
      _explaining = false;
      _draftingTransfer = false;
      // Free the single model queue instead of letting dead work pile up.
      advanced?.cancelPending();
    }
  }

  final TransactionRepository repo;
  final SearchRunner engine;
  final PlanValidator validator;

  /// Free-text interpretation for standard mode.
  final StandardInterpreter? interpreter;

  /// Rule-based follow-ups for standard mode.
  final RuleRefiner? refiner;
  final void Function(TimingSample sample)? onTiming;

  /// Called after a memo is saved, before the search reruns (Task 16 wires
  /// the index refresh here).
  final Future<void> Function(String txnId)? onMemoChanged;

  final ResultPager pager = ResultPager();

  SearchPlan _plan = SearchPlan.empty;
  ResultSummary? _summary;
  String? _notice;
  List<String> _errors = const [];
  bool _busy = false;
  Explanation? _explanation;
  bool _explaining = false;
  int _explainGeneration = 0;
  TransferDraft? _transferDraft;
  bool _draftingTransfer = false;
  int _draftGeneration = 0;
  bool _disposed = false;
  int _generation = 0;
  String? _lastQuery;
  // False once the plan was changed without a query (chip edit, browse): the
  // old natural-language text no longer describes the rows on screen.
  bool _queryCurrent = false;
  Map<Stage, Duration> _lastTimings = const {};

  SearchPlan get plan => _plan;
  ResultSummary? get summary => _summary;
  String? get notice => _notice;
  List<String> get errors => _errors;
  bool get busy => _busy;
  Explanation? get explanation => _explanation;
  bool get explaining => _explaining;
  TransferDraft? get transferDraft => _transferDraft;
  bool get draftingTransfer => _draftingTransfer;
  bool get canDraftTransfer =>
      (advanced?.isOn ?? false) &&
      pager.items
          .take(kMaxExplainRows)
          .any((t) => t.type == TransactionType.transfer);
  String? get lastQuery => _lastQuery;
  Map<Stage, Duration> get lastTimings => _lastTimings;

  void _showErrors(List<String> errors) {
    _errors = errors;
    notifyListeners();
  }

  /// Clears the query and filters: the newest 100 transactions.
  Future<void> browse() {
    _invalidateExplanation();
    _lastQuery = null;
    return applyPlan(SearchPlan.empty);
  }

  /// Interprets [query] and runs it immediately via deterministic rules + SQL +
  /// RAG so the list updates ASAP (unless [useAdvancedPlanner] is enabled).
  /// An empty query browses.
  Future<void> submit(String query, {bool? useAdvancedPlanner}) async {
    final q = query.trim();
    if (q.isEmpty) return browse();
    final since = Stopwatch()..start();
    final timer = StageTimer();
    final gen = ++_generation;
    _invalidateExplanation();
    _busy = true;
    _errors = const [];
    notifyListeners();

    final advanced = this.advanced;
    final planWithGemma = useAdvancedPlanner ?? this.useAdvancedPlanner;
    if (planWithGemma && advanced != null && advanced.isOn) {
      await _advancedPlan(gen, () => advanced.plan(q), timer, since, q);
      return;
    }
    final interpreter = this.interpreter;
    if (interpreter == null) throw StateError('No interpreter configured');
    final plan = await timer.time(
      Stage.interpret,
      () => interpreter.interpret(q),
    );
    if (gen != _generation) return;
    await applyPlan(
      plan,
      timer: timer,
      since: since,
      query: q,
      advanced: false,
    );
  }

  Future<void> refine(String followUp, {bool? useAdvancedPlanner}) async {
    final text = followUp.trim();
    if (text.isEmpty) return;
    final advanced = this.advanced;
    final planWithGemma = useAdvancedPlanner ?? this.useAdvancedPlanner;
    if (planWithGemma && advanced != null && advanced.isOn) {
      final gen = ++_generation;
      _invalidateExplanation();
      _busy = true;
      _errors = const [];
      notifyListeners();
      final current = _plan;
      // After a chip edit the old question no longer describes the filters.
      final previous = _queryCurrent ? _lastQuery : null;
      await _advancedPlan(
        gen,
        () => advanced.plan(text, current: current, previousQuery: previous),
        StageTimer(),
        Stopwatch()..start(),
        text,
      );
      return;
    }
    final refiner = this.refiner;
    if (refiner == null) return;
    await applyPlan(refiner.refine(_plan, text), query: text, advanced: false);
  }

  Future<void> _advancedPlan(
    int gen,
    Future<SearchPlan> Function() planWithGemma,
    StageTimer timer,
    Stopwatch since,
    String query,
  ) async {
    _planningAdvanced = true;
    try {
      final plan = await timer.time(Stage.interpret, planWithGemma);
      if (gen != _generation || !(advanced?.isOn ?? false)) return;
      await applyPlan(
        plan,
        timer: timer,
        since: since,
        query: query,
        advanced: true,
      );
    } on GemmaCancelled {
      if (gen == _generation) {
        _busy = false;
        _planningAdvanced = false;
        notifyListeners();
      }
    } on AdvancedError catch (e) {
      if (gen == _generation) {
        _busy = false;
        _planningAdvanced = false;
        _errors = [e.message]; // previous chips and rows stay
        notifyListeners();
      }
    }
  }

  /// Validates and runs [plan]. An invalid plan keeps the current chips and
  /// rows and shows the errors instead.
  Future<void> applyPlan(
    SearchPlan plan, {
    StageTimer? timer,
    Stopwatch? since,
    String? query,
    bool? advanced,
  }) async {
    final gen = ++_generation;
    _invalidateExplanation();
    // A chip edit or memo rerun outdates any in-flight advanced plan; free the
    // model queue so a following Explain does not wait behind it.
    if (advanced != true) this.advanced?.cancelPending();
    final advancedMode = advanced ?? (this.advanced?.isOn ?? false);
    final watch = since ?? (Stopwatch()..start());
    final t = timer ?? StageTimer();
    final validation = validator.validate(plan);
    if (!validation.isValid) {
      // The bumped generation discards any in-flight search, so nothing else
      // will ever clear `busy`.
      _busy = false;
      _showErrors(validation.errors);
      return;
    }
    final valid = validation.plan!;
    // Only the explicit Gemma path is cancellable by toggle-off; chip edits and
    // memo reruns are plain SQL and must land.
    _planningAdvanced = advanced == true;
    _errors = const [];
    _busy = true;
    notifyListeners();
    try {
      final outcome = await engine.run(valid, t);
      if (gen != _generation) return;
      _lastQuery = query ?? _lastQuery;
      _queryCurrent = query != null;
      _plan = outcome.plan;
      _summary = outcome.summary;
      _notice = outcome.notice;
      notifyListeners();
      await t.time(Stage.rowFetch, () => pager.start(outcome.source));
      if (gen != _generation) return;
      if (pager.status == PagerStatus.firstPageError) {
        throw StateError('Could not load the first page: ${pager.error}');
      }
      t.add(Stage.total, watch.elapsed);
      _lastTimings = t.durations;
      onTiming?.call(
        TimingSample(
          query: query ?? _lastQuery ?? '',
          advanced: advancedMode,
          semantic: valid.hasSemanticIntent,
          stages: t.durations,
        ),
      );
    } catch (e) {
      if (gen == _generation) _errors = ['Search failed: $e'];
    } finally {
      if (gen == _generation) {
        _busy = false;
        _planningAdvanced = false;
        notifyListeners();
      }
    }
  }

  /// Grounded explanation of the first rows on screen (advanced mode only).
  ///
  /// Own token (`_explainGeneration`): any new search, chip edit, dismissal or
  /// toggle-off bumps it, so a late result can never land. Rows, chips and the
  /// query are never touched; failures only add a message to [errors].
  Future<void> explain() async {
    final advanced = this.advanced;
    if (advanced == null || !advanced.isOn || _disposed) return;
    // One native job at a time: ignore presses while explaining, drafting or searching.
    if (_explaining || _draftingTransfer || _busy) return;
    final rows = pager.items.take(kMaxExplainRows).toList();
    if (rows.isEmpty) return;
    final token = ++_explainGeneration;
    _explaining = true;
    _explanation = null;
    _errors = const [];
    notifyListeners();
    final timer = StageTimer();
    try {
      // Never send query text that no longer describes the rows on screen.
      final query = _queryCurrent ? (_lastQuery ?? '') : '';
      final result = await timer.time(
        Stage.answer,
        () => advanced.explain(query, rows, plan: _plan),
      );
      if (token != _explainGeneration) return;
      _explanation = result;
      _lastTimings = {..._lastTimings, ...timer.durations};
    } on GemmaCancelled {
      // switched off or pre-empted by a new search: nothing to show
    } on AdvancedError catch (e) {
      if (token == _explainGeneration) _errors = [e.message];
    } catch (e) {
      // Catch-all: `explaining` must never stick on.
      if (token == _explainGeneration) _errors = ['Explanation failed: $e'];
    } finally {
      if (token == _explainGeneration) {
        _explaining = false;
        notifyListeners();
      }
    }
  }

  /// Hides the explanation. An in-flight one is cancelled and cannot reappear.
  void dismissExplanation() {
    ++_explainGeneration;
    _explanation = null;
    if (_explaining) {
      _explaining = false;
      advanced?.cancelPending();
    }
    notifyListeners();
  }

  /// Prepares a repeat transfer from the transfer rows on screen (advanced mode
  /// only): Gemma calls `draft_transfer` and the deterministic post-hook
  /// cross-checks the source ID, recipient, and SQLite satang amount.
  Future<void> draftTransfer() async {
    final advanced = this.advanced;
    if (advanced == null || !advanced.isOn || _disposed) return;
    if (_explaining || _draftingTransfer || _busy) return;
    final rows = pager.items
        .take(kMaxExplainRows)
        .where((t) => t.type == TransactionType.transfer)
        .toList();
    if (rows.isEmpty) return;
    final token = ++_draftGeneration;
    _draftingTransfer = true;
    _transferDraft = null;
    _errors = const [];
    notifyListeners();
    final timer = StageTimer();
    try {
      final query = _queryCurrent ? (_lastQuery ?? '') : '';
      final result = await timer.time(
        Stage.answer,
        () => advanced.draftTransfer(query, rows),
      );
      if (token != _draftGeneration) return;
      _transferDraft = result;
      _lastTimings = {..._lastTimings, ...timer.durations};
    } on GemmaCancelled {
      // switched off or pre-empted by a new search: nothing to show
    } on AdvancedError catch (e) {
      if (token == _draftGeneration) _errors = [e.message];
    } catch (e) {
      if (token == _draftGeneration) _errors = ['Draft transfer failed: $e'];
    } finally {
      if (token == _draftGeneration) {
        _draftingTransfer = false;
        notifyListeners();
      }
    }
  }

  /// Hides the transfer draft. An in-flight one is cancelled.
  void dismissTransferDraft() {
    ++_draftGeneration;
    _transferDraft = null;
    if (_draftingTransfer) {
      _draftingTransfer = false;
      advanced?.cancelPending();
    }
    notifyListeners();
  }

  /// Saves (or clears) a memo, refreshes its index entry, reruns the search.
  Future<Transaction> updateMemo(String id, String? memo) async {
    // An explanation built from the old memo must not appear after the save.
    _invalidateExplanation();
    notifyListeners();
    final updated = await repo.updateMemo(id, memo);
    await onMemoChanged?.call(id);
    await applyPlan(_plan, query: _queryCurrent ? _lastQuery : null);
    return updated;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _explainGeneration++;
    _draftGeneration++;
    advanced?.removeListener(_advancedChanged);
    pager.dispose();
    super.dispose();
  }
}
