import 'dart:async';

import '../app_services.dart';
import '../core/transaction.dart';
import '../perf/stage_timer.dart';
import '../search/plan_matcher.dart';
import '../search/plan_validator.dart';
import '../search/search_plan.dart';
import 'eval_queries.dart';
import 'plan_scoring.dart';

/// One query's Advanced result, for the outcome table.
class _AdvancedRow {
  _AdvancedRow(this.id, this.outcome, this.planMs, this.detail);
  final String id;
  final AdvancedOutcome outcome;
  final double planMs;
  final String detail;
}

/// Runs kEvalQueries through the real app pipeline and returns a markdown
/// report (spec §13 metrics). [advanced] runs with the switch on: the same
/// table plus per-query outcomes (plan / rejected / errored), planning
/// latency and per-field plan scoring. A rejected, failed or hung Gemma query
/// is recorded and the run continues; it never throws.
///
/// [queryTimeout] only guards the Advanced run (the controller's own 20 s
/// planning deadline normally fires first).
Future<String> runEvaluation(
  AppServices services, {
  required bool advanced,
  Duration queryTimeout = const Duration(seconds: 60),
}) async {
  final search = services.search;
  final validator = PlanValidator(services.directory);
  final rows = <String>[
    '| id | kind | plan ok | rows | violations | recall@5 | precision@5 | pass | total ms |',
    '|---|---|---|---|---|---|---|---|---|',
  ];
  var planOk = 0;
  var planChecked = 0;
  var violations = 0;
  final recalls = <double>[];
  final precisions = <double>[];
  final failures = <String>[];
  final advancedRows = <_AdvancedRow>[];
  final fieldTotals = <PlanField, PlanFieldScore>{};
  var scoredQueries = 0;

  Future<List<Transaction>> allRows() async {
    while (search.pager.canLoadMore) {
      await search.pager.loadMore();
    }
    return search.pager.items;
  }

  /// Runs [body]. In an Advanced run any error or hang becomes a message.
  Future<String?> guarded(Future<void> Function() body) async {
    if (!advanced) {
      await body();
      return null;
    }
    try {
      await body().timeout(queryTimeout);
      return null;
    } on TimeoutException {
      services.advanced?.cancelPending();
      return 'Evaluation guard: no result after ${queryTimeout.inMilliseconds / 1000} s.';
    } catch (e) {
      return 'Evaluation error: $e';
    }
  }

  /// What the last guarded call produced. Only meaningful in an Advanced run.
  (AdvancedOutcome, String) outcomeOf(String queryText, String? guardError) {
    if (guardError != null) return (AdvancedOutcome.errored, guardError);
    if (search.errors.isNotEmpty) {
      final message = search.errors.join(' ');
      return (classifyAdvancedFailure(message), message);
    }
    if (search.lastQuery != queryText) {
      return (AdvancedOutcome.noResult, 'No plan landed (cancelled or superseded).');
    }
    return (AdvancedOutcome.plan, '');
  }

  double planMillis(Stopwatch watch) {
    final interpret = search.lastTimings[Stage.interpret];
    return (interpret ?? watch.elapsed).inMicroseconds / 1000;
  }

  void scoreAdvanced(EvalQuery q, SearchPlan got, double ms, String baseNote) {
    var detail = baseNote;
    final expected = q.expected;
    if (expected != null) {
      final score = scorePlan(validator.validate(expected).plan!, got);
      addScores(fieldTotals, score);
      scoredQueries++;
      final diffs = describeScore(score);
      detail = [if (diffs.isEmpty) 'exact' else diffs.join('; '), if (baseNote.isNotEmpty) baseNote]
          .join('; ');
    }
    advancedRows.add(_AdvancedRow(q.id, AdvancedOutcome.plan, ms, detail));
  }

  void recordNoPlan(EvalQuery q, AdvancedOutcome outcome, double ms, String message, String baseNote) {
    advancedRows.add(_AdvancedRow(q.id, outcome, ms, [message, if (baseNote.isNotEmpty) baseNote].join(' ')));
    rows.add('| ${q.id} | ${q.kind.name} | no plan | - | - | - | - | ${outcome.name.toUpperCase()} | '
        '${ms.toStringAsFixed(0)} |');
  }

  for (final q in kEvalQueries) {
    // Advanced runs start each query from a clean screen, so a rejected query
    // can never be mistaken for the previous query's plan.
    if (advanced) await search.browse();
    final watch = Stopwatch()..start();
    var baseNote = '';
    switch (q.kind) {
      case EvalKind.followUp:
        final baseText = evalQuery(q.followUpOf!).text;
        final baseError = await guarded(() => search.submit(baseText));
        if (advanced) {
          final (baseOutcome, baseMessage) = outcomeOf(baseText, baseError);
          if (baseOutcome != AdvancedOutcome.plan) {
            baseNote = '(base ${q.followUpOf} ${baseOutcome.name}: $baseMessage)';
          }
        }
        watch
          ..reset()
          ..start();
        final error = await guarded(() => search.refine(q.text));
        if (advanced) {
          final (outcome, message) = outcomeOf(q.text, error);
          if (outcome != AdvancedOutcome.plan) {
            recordNoPlan(q, outcome, planMillis(watch), message, baseNote);
            continue;
          }
        }
      case EvalKind.memoEdit:
        const original = 'Groceries for the housewarming party';
        late bool afterEdit;
        late bool restored;
        (AdvancedOutcome, String) first = (AdvancedOutcome.plan, '');
        (AdvancedOutcome, String) second = (AdvancedOutcome.plan, '');
        SearchPlan? firstPlan;
        var ms = 0.0;
        try {
          await search.updateMemo('txn_a29', 'Snacks for the office');
          watch
            ..reset()
            ..start();
          final e1 = await guarded(() => search.submit(q.text));
          first = outcomeOf(q.text, e1);
          ms = planMillis(watch);
          firstPlan = search.plan;
          afterEdit = (await allRows()).any((t) => t.id == 'txn_a29');
        } finally {
          // Never leave the edited memo behind, even if a guard fired.
          await search.updateMemo('txn_a29', original);
        }
        final e2 = await guarded(() => search.submit(q.text));
        second = outcomeOf(q.text, e2);
        restored = (await allRows()).any((t) => t.id == 'txn_a29');
        if (advanced && (first.$1 != AdvancedOutcome.plan || second.$1 != AdvancedOutcome.plan)) {
          final bad = first.$1 != AdvancedOutcome.plan ? first : second;
          recordNoPlan(q, bad.$1, ms, bad.$2, '');
          continue;
        }
        final pass = !afterEdit && restored;
        if (!pass) failures.add('E25 memo edit: afterEdit=$afterEdit restored=$restored');
        if (advanced) scoreAdvanced(q, firstPlan, ms, '');
        rows.add('| ${q.id} | memoEdit | - | - | - | - | - | ${pass ? 'PASS' : 'FAIL'} | - |');
        continue;
      default:
        final error = await guarded(() => search.submit(q.text));
        if (advanced) {
          final (outcome, message) = outcomeOf(q.text, error);
          if (outcome != AdvancedOutcome.plan) {
            recordNoPlan(q, outcome, planMillis(watch), message, '');
            continue;
          }
        }
    }
    final plan = search.plan;
    final got = await allRows();
    final v = got.where((t) => !planMatches(plan, t)).length;
    violations += v;
    if (advanced) scoreAdvanced(q, plan, planMillis(watch), baseNote);

    String ok = '-';
    if (q.expected != null) {
      planChecked++;
      final expected = validator.validate(q.expected!).plan!;
      final same = scorePlan(expected, plan).values.every((s) => s.isExact);
      if (same) planOk++;
      ok = same ? 'yes' : 'NO';
      if (!same) failures.add('${q.id} plan: expected $expected got $plan');
    }

    var recall = '-';
    var precision = '-';
    var pass = v == 0;
    if (q.relevant.isNotEmpty) {
      final top5 = got.take(5).map((t) => t.id).toSet();
      if (q.relevant.length <= 5) {
        final r = top5.intersection(q.relevant).length / q.relevant.length;
        recalls.add(r);
        recall = r.toStringAsFixed(2);
        pass = pass && r >= 0.9;
      }
      if (top5.isNotEmpty) {
        final p = top5.intersection({...q.relevant, ...q.acceptable}).length / top5.length;
        precisions.add(p);
        precision = p.toStringAsFixed(2);
      }
    }
    if (q.kind == EvalKind.noMatch) pass = pass && got.isEmpty;
    if (!pass) failures.add('${q.id}: rows=${got.length} top5=${got.take(5).map((t) => t.id).toList()}');
    final total = search.lastTimings[Stage.total];
    rows.add('| ${q.id} | ${q.kind.name} | $ok | ${got.length} | $v | $recall | $precision | '
        '${pass ? 'PASS' : 'FAIL'} | ${total == null ? '-' : (total.inMicroseconds / 1000).toStringAsFixed(0)} |');
  }

  double mean(List<double> xs) => xs.isEmpty ? double.nan : xs.reduce((a, b) => a + b) / xs.length;
  await search.browse();

  int count(AdvancedOutcome o) => advancedRows.where((r) => r.outcome == o).length;
  final planMs = advancedRows.map((r) => r.planMs).toList();
  return [
    '## ${advanced ? 'Advanced' : 'Standard'} evaluation: fixture ${services.fixtureSize}',
    '',
    ...rows,
    '',
    '- plan accuracy: $planOk / $planChecked',
    '- hard-filter violations: $violations',
    '- mean recall@5 (|R| <= 5): ${mean(recalls).toStringAsFixed(3)}',
    '- mean precision@5: ${mean(precisions).toStringAsFixed(3)}',
    '- Gemma jobs started so far: ${services.advanced?.jobsStarted ?? 0}',
    if (failures.isNotEmpty) ...['', '### Failures', for (final f in failures) '- $f'],
    if (advanced) ...[
      '',
      '### Advanced outcomes and planning latency',
      '',
      'Plan ${count(AdvancedOutcome.plan)}, rejected ${count(AdvancedOutcome.rejected)}, '
          'errored ${count(AdvancedOutcome.errored)}, no result ${count(AdvancedOutcome.noResult)} '
          'of ${advancedRows.length}. Recall, precision, violations and plan accuracy above '
          'cover only queries where Gemma returned a plan.',
      '- planning ms: mean ${mean(planMs).toStringAsFixed(0)}, '
          'max ${planMs.isEmpty ? '-' : planMs.reduce((a, b) => a > b ? a : b).toStringAsFixed(0)}',
      '',
      '| id | outcome | planning ms | detail |',
      '|---|---|---|---|',
      for (final r in advancedRows)
        '| ${r.id} | ${r.outcome.name} | ${r.planMs.toStringAsFixed(0)} | '
            '${r.detail.replaceAll('|', '/').replaceAll('\n', ' ')} |',
      '',
      '### Advanced per-field plan scoring (report only, no pass bar)',
      '',
      renderFieldTotals(fieldTotals, scoredQueries),
    ],
  ].join('\n');
}
