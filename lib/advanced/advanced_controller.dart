import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, setEquals;

import '../core/payees.dart';
import '../core/transaction.dart';
import '../search/plan_validator.dart';
import '../search/rules/amount_rules.dart';
import '../search/rules/date_rules.dart';
import '../search/rules/rule_parser.dart';
import '../search/rules/rule_refiner.dart';
import '../search/rules/text_spans.dart';
import '../search/search_plan.dart';
import 'explainer.dart';
import 'gemma_installer.dart';
import 'gemma_runtime.dart';
import 'gemma_tool.dart';
import 'plan_args.dart';
import 'planning_prompt.dart';
import 'transfer_drafter.dart';

enum ModelInstallState { unknown, notInstalled, downloading, installed, failed }

enum AdvancedToggle { off, enabling, on }

class AdvancedError implements Exception {
  const AdvancedError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Owns the model lifecycle and its single conversation queue. Cancellation
/// settles callers immediately; the queue still waits for native cleanup before
/// starting another conversation or unloading. Late results never change state.
class AdvancedController extends ChangeNotifier {
  AdvancedController({
    required this.installer,
    required this.runtime,
    required this.directory,
    this.planTimeout = const Duration(seconds: 20),
    this.explainTimeout = const Duration(seconds: 30),
  });

  final GemmaInstaller installer;
  final GemmaRuntime runtime;
  final PayeeDirectory directory;
  final Duration planTimeout;
  final Duration explainTimeout;

  ModelInstallState _install = ModelInstallState.unknown;
  int _progress = 0;
  AdvancedToggle _toggle = AdvancedToggle.off;
  String? _error;
  GemmaCancelSignal? _download;
  Future<void>? _downloadTask;
  int _generation = 0;
  int _installRevision = 0;
  Future<void> _lifecycle = Future.value();
  Future<void> _queue = Future.value();
  Future<bool>? _enabling;
  final Set<_GemmaJob> _pending = {};
  _GemmaJob? _active;
  int _jobs = 0;
  bool _disposed = false;

  ModelInstallState get install => _install;
  int get downloadProgress => _progress;
  AdvancedToggle get toggle => _toggle;
  String? get error => _error;
  bool get isOn => _toggle == AdvancedToggle.on;
  int get jobsStarted => _jobs;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refreshInstallState() async {
    if (_download != null || _disposed) return;
    final revision = ++_installRevision;
    try {
      final installed = await installer.isInstalled();
      if (revision != _installRevision || _disposed) return;
      _install = installed
          ? ModelInstallState.installed
          : ModelInstallState.notInstalled;
      _error = null;
    } catch (e) {
      if (revision != _installRevision || _disposed) return;
      _install = ModelInstallState.failed;
      _error = 'Could not check the model: $e';
    }
    _notify();
  }

  /// False asks the UI to open setup. True means installation was found;
  /// callers read [toggle] and [error] to distinguish a load failure.
  Future<bool> requestEnable() {
    if (_disposed) return Future.value(false);
    if (isOn) return Future.value(true);
    final downloading = _downloadTask;
    if (downloading != null && !(_download?.isCancelled ?? true)) {
      final gen = _generation;
      return downloading.then(
        (_) => _current(gen) && _install == ModelInstallState.installed,
      );
    }
    // Cancelled setup no longer owns a fresh switch-on intent. Queue this
    // enable after the old download and any disable cleanup, then check the
    // verified file and current generation before loading.
    final enabling = _enabling;
    if (enabling != null) return enabling;
    final gen = _generation;
    final future = _serializeLifecycle(() async {
      if (!_current(gen)) return false;
      if (_install != ModelInstallState.installed) await refreshInstallState();
      if (!_current(gen) || _install != ModelInstallState.installed) {
        return false;
      }
      if (!isOn) await _load(gen);
      return true;
    });
    _enabling = future;
    unawaited(
      future.then((_) {
        if (identical(_enabling, future)) _enabling = null;
      }),
    );
    return future;
  }

  Future<void> downloadAndEnable() {
    if (_disposed || isOn) return Future.value();
    if (_download != null) return _downloadTask ?? Future.value();
    final enabling = _enabling;
    if (_toggle == AdvancedToggle.enabling && enabling != null) {
      return enabling.then<void>((_) {});
    }
    final signal = GemmaCancelSignal();
    _download = signal;
    ++_installRevision;
    final gen = _generation;
    _install = ModelInstallState.downloading;
    _progress = 0;
    _error = null;
    _notify();
    final future = _serializeLifecycle(() async {
      try {
        if (!_current(gen) || signal.isCancelled) {
          throw const GemmaDownloadCancelled();
        }
        await installer.install(
          onProgress: (p) {
            if (!_current(gen) || signal.isCancelled) return;
            _progress = p.clamp(0, 100);
            _notify();
          },
          cancel: signal,
        );
        // The adapter must verify the downloaded file, not just report 100%.
        if (!await installer.isInstalled()) {
          throw const AdvancedError(
            'The model download could not be verified.',
          );
        }
        _install = ModelInstallState.installed;
        if (!_current(gen) || signal.isCancelled) {
          throw const GemmaDownloadCancelled();
        }
        _notify();
        await _load(gen);
        if (signal.isCancelled) throw const GemmaDownloadCancelled();
      } on GemmaDownloadCancelled {
        // A cancelled adapter may have completed the file before noticing cancel.
        try {
          _install = await installer.isInstalled()
              ? ModelInstallState.installed
              : ModelInstallState.notInstalled;
        } catch (_) {
          _install = ModelInstallState.notInstalled;
        }
        _error = 'Download cancelled.';
      } catch (e) {
        _install = ModelInstallState.failed;
        _error = 'Download failed: $e';
      } finally {
        if (identical(_download, signal)) {
          _download = null;
          _downloadTask = null;
        }
        _notify();
      }
    });
    _downloadTask = future;
    return future;
  }

  void cancelDownload() {
    final signal = _download;
    signal?.cancel();
    if (signal != null && _toggle == AdvancedToggle.enabling) {
      unawaited(disable());
    }
  }

  bool _current(int gen) => !_disposed && gen == _generation;

  Future<void> _load(int gen) async {
    if (!_current(gen)) return;
    _toggle = AdvancedToggle.enabling;
    _error = null;
    _notify();
    try {
      await installer.activate();
      if (!_current(gen)) return;
      await runtime.load();
    } catch (e) {
      // A failed load can still allocate native resources.
      try {
        await runtime.unload();
      } catch (_) {
        /* Keep the original failure. */
      }
      if (_current(gen)) {
        _toggle = AdvancedToggle.off;
        _error = 'Could not load Gemma: $e';
        _notify();
      }
      return;
    }
    // disable has already queued unload after this lifecycle operation.
    if (!_current(gen)) return;
    _toggle = AdvancedToggle.on;
    _notify();
  }

  /// Publishes off and cancels callers immediately. Cleanup waits for any
  /// uncancellable native load/generation to finish before unloading safely.
  Future<void> disable() {
    ++_generation;
    _toggle = AdvancedToggle.off;
    _enabling = null;
    _download?.cancel();
    _invalidateJobs();
    _notify();
    return _serializeLifecycle(() async {
      await _queue;
      try {
        await runtime.unload();
      } catch (e) {
        _error = 'Could not close Gemma: $e';
        _notify();
      }
    });
  }

  Future<SearchPlan> plan(
    String query, {
    SearchPlan? current,
    String? previousQuery,
  }) async {
    _requireOn();
    // A newer question also supersedes queued questions and explanations.
    _invalidateJobs();
    final args = await _enqueue(
      () => runtime.callTool(
        system: buildPlanningSystemPrompt(
          shops: directory.shopNames,
          people: directory.personNames,
        ),
        user: current == null
            ? buildPlanningUserTurn(query)
            : buildFollowUpUserTurn(
                followUp: query,
                previousQuery: previousQuery,
                current: current,
              ),
        tool: kSearchTool,
        timeout: planTimeout,
      ),
      timeout: planTimeout,
    );
    final conversion = planFromToolArgs(
      args,
      current: current,
      directory: directory,
    );
    if (!conversion.isValid) throw _invalidPlan(conversion.errors);
    final validated = PlanValidator(directory).validate(conversion.plan!);
    if (!validated.isValid) throw _invalidPlan(validated.errors);
    _checkDates(query, validated.plan!, current);
    _checkPayees(query, validated.plan!);
    _checkAmounts(query, validated.plan!, current);
    return validated.plan!;
  }

  AdvancedError _invalidPlan(List<String> errors) => AdvancedError(
    'Gemma returned filters the app cannot use: ${errors.join(' ')}',
  );

  static final RegExp _bareYear = RegExp(r'^20\d{2}$');
  static final RegExp _calendarYearRange = RegExp(
    r'\b(?:between|from)\s+20\d{2}\s+(?:and|to|until|through|-)\s+20\d{2}\b'
    r'(?!\d|[.,]\d)(?!\s*(?:thb|baht|฿))',
  );

  void _checkPayees(String query, SearchPlan plan) {
    final requested = RuleParser(directory: directory).parse(query);
    if ((requested.shopNames.isNotEmpty && !setEquals(requested.shopNames, plan.shopNames)) ||
        (requested.personNames.isNotEmpty && !setEquals(requested.personNames, plan.personNames))) {
      throw const AdvancedError('Gemma did not preserve the requested payees. '
          'Try rephrasing, or turn Advanced reasoning off.');
    }
  }

  void _checkDates(String query, SearchPlan plan, SearchPlan? current) {
    if (current?.dateRange != null) {
      final refined = RuleRefiner(RuleParser(directory: directory)).refine(current!, query);
      if (refined.dateRange != current.dateRange && plan.dateRange != refined.dateRange) {
        throw const AdvancedError('Gemma did not preserve the requested dates. '
            'Try rephrasing, or turn Advanced reasoning off.');
      }
    }
    final text = QueryText(query);
    for (final alias in directory.phrases) {
      text.take(joinPattern(['(?<![a-z0-9])', RegExp.escape(alias.phrase), '(?![a-z0-9])']));
    }
    // Numeric money and multi-year calendar requests are not single date phrases.
    text.take(_calendarYearRange);
    const AmountRules().apply(text);
    final dates = DateRules().apply(text);
    // Audit only an unambiguous phrase the existing rules can resolve. More
    // complex Gemma calendar reasoning remains visible in the editable chips.
    if (dates.matches.length != 1 || dates.notes.any((n) => n.kind == PlanNoteKind.ambiguous)) return;
    if (plan.dateRange != dates.matches.single.range) {
      throw const AdvancedError('Gemma did not preserve the requested dates. '
          'Try rephrasing, or turn Advanced reasoning off.');
    }
  }

  void _checkAmounts(String query, SearchPlan plan, SearchPlan? current) {
    final text = QueryText(query);
    final calendarText = QueryText(query);
    // Protect numeric payees before probing calendars or amounts.
    for (final alias in directory.phrases) {
      final pattern = joinPattern([
        '(?<![a-z0-9])',
        RegExp.escape(alias.phrase),
        '(?![a-z0-9])',
      ]);
      text.take(pattern);
      calendarText.take(pattern);
    }
    for (final date in DateRules().apply(calendarText).matches) {
      // A bare year is also a valid money operand after under/over/exactly.
      // Full calendar phrases (ISO dates, month/year, etc.) remain protected.
      if (!_bareYear.hasMatch(date.text)) {
        text.take(RegExp(RegExp.escape(date.text.toLowerCase())));
      }
    }
    // Currency-free year ranges are calendar requests, unlike single
    // operator-qualified amounts. A currency suffix keeps the range monetary.
    text.take(_calendarYearRange);
    final explicit = const AmountRules().apply(text);
    if (explicit.min == null && explicit.max == null) {
      // The user named only a non-THB amount ("under \$50", "over 100 dollars").
      // The standard parser applies no filter and says so; a model that
      // introduces an amount anyway has invented a THB limit. Reject, do not repair.
      final foreign = explicit.notes.any((n) => n.text.startsWith('Only THB amounts are supported'));
      if (foreign && (plan.minAmount != current?.minAmount || plan.maxAmount != current?.maxAmount)) {
        throw const AdvancedError(
          'Only THB amounts are supported, but Gemma applied an amount limit. '
          'Try rephrasing in THB, or turn Advanced reasoning off.',
        );
      }
      return;
    }
    // Compare the merged plan, so omitted unchanged follow-up fields remain valid.
    // Never repair Gemma's response by silently inserting a missing constraint.
    final expectedMin = explicit.min ?? current?.minAmount;
    final expectedMax = explicit.max ?? current?.maxAmount;
    if (plan.minAmount != expectedMin || plan.maxAmount != expectedMax) {
      throw const AdvancedError(
        'Gemma did not preserve the requested THB amount limits. '
        'Try rephrasing, or turn Advanced reasoning off.',
      );
    }
  }

  Future<Explanation> explain(
    String query,
    List<Transaction> rows, {
    SearchPlan? plan,
  }) async {
    _requireOn();
    final selected = rows.take(kMaxExplainRows).toList();
    if (selected.isEmpty) throw const AdvancedError('Nothing to explain.');
    final text = await _enqueue(
      () => runtime.generate(
        system: kExplainSystemPrompt,
        user: buildExplainUserTurn(query, selected, plan: plan),
        timeout: explainTimeout,
      ),
      timeout: explainTimeout,
    );
    return validateExplanation(text, {for (final row in selected) row.id});
  }

  /// Prepares a repeat transfer from retrieved transfer rows via a forced
  /// `draft_transfer` tool call, verified by [validateTransferDraft].
  Future<TransferDraft> draftTransfer(
    String query,
    List<Transaction> rows,
  ) async {
    _requireOn();
    final transfers = rows
        .where((t) => t.type == TransactionType.transfer)
        .take(kMaxDraftRows)
        .toList();
    if (transfers.isEmpty) {
      throw const AdvancedError(
        'No transfer transactions in the current results to repeat.',
      );
    }
    final args = await _enqueue(
      () => runtime.callTool(
        system: kDraftTransferSystemPrompt,
        user: buildDraftTransferUserTurn(query, transfers),
        tool: kDraftTransferTool,
        timeout: explainTimeout,
      ),
      timeout: explainTimeout,
    );
    return validateTransferDraft(args, transfers);
  }

  /// Cancels the running and queued model jobs (for example a dismissed
  /// explanation) without turning Advanced reasoning off.
  void cancelPending() => _invalidateJobs();

  void _requireOn() {
    if (!isOn || _disposed) {
      throw const AdvancedError('Advanced reasoning is off.');
    }
  }

  void _checkJob(_GemmaJob job) {
    if (job.cancelled.isCompleted || !_current(job.generation) || !isOn) {
      throw const GemmaCancelled();
    }
  }

  void _invalidateJobs() {
    for (final job in _pending) {
      if (!job.cancelled.isCompleted) job.cancelled.complete();
    }
    final active = _active;
    if (active != null && active.stop == null) {
      active.stop = _cancelRuntime();
    }
  }

  Future<void> _cancelRuntime() async {
    try {
      await runtime.cancel();
    } catch (e) {
      _error = 'Could not cancel Gemma: $e';
      _notify();
    }
  }

  Future<T> _enqueue<T>(
    Future<T> Function() call, {
    required Duration timeout,
  }) {
    final job = _GemmaJob(_generation);
    _pending.add(job);
    final execution = _queue.then((_) async {
      // Essential: queued stale jobs must never reach the native runtime.
      _checkJob(job);
      _active = job;
      _jobs++;
      try {
        final result = await call();
        _checkJob(job);
        return result;
      } catch (e) {
        _checkJob(job);
        if (e is GemmaCancelled) rethrow;
        if (e is GemmaNoToolCall) {
          throw const AdvancedError(
            'Gemma answered without filters. '
            'Try rephrasing, or turn Advanced reasoning off.',
          );
        }
        if (e is GemmaTimeout) {
          // Runtime contract stops native generation before throwing timeout.
          throw AdvancedError('Gemma took longer than ${timeout.inSeconds} s.');
        }
        throw AdvancedError('Gemma could not complete the request: $e');
      } finally {
        // A slow cancellation must not stop the next queued conversation.
        await job.stop;
        if (identical(_active, job)) _active = null;
      }
    });
    _queue = execution.then<void>((_) {}, onError: (Object _) {}).whenComplete(
      () {
        _pending.remove(job);
      },
    );
    return Future.any<T>([
      execution,
      job.cancelled.future.then<T>((_) => throw const GemmaCancelled()),
    ]);
  }

  Future<T> _serializeLifecycle<T>(Future<T> Function() operation) {
    final result = _lifecycle.then((_) => operation());
    _lifecycle = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(disable());
    super.dispose();
  }
}

class _GemmaJob {
  _GemmaJob(this.generation);
  final int generation;
  final Completer<void> cancelled = Completer<void>();
  Future<void>? stop;
}
