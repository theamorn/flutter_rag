import 'dart:io';

import '../app_services.dart';
import '../perf/stage_timer.dart';
import '../perf/timing_log.dart';
import 'eval_queries.dart';

/// Five measured passes by default, after a discarded warm-up for each mode.
/// Advanced failures have their own latency table; successful searches alone
/// contribute to the submit-to-first-rows stage table.
Future<String> runBenchmark(
  AppServices services, {
  int reps = 5,
  bool advanced = false,
}) async {
  if (reps < 1) throw ArgumentError.value(reps, 'reps', 'must be positive');
  final search = services.search;
  final log = services.timingLog;
  final adv = services.advanced;
  if (adv != null) await adv.disable();
  final queries = [
    for (final q in kEvalQueries)
      if (q.kind != EvalKind.memoEdit && q.kind != EvalKind.followUp) q,
  ];
  final failures = <String>[];
  final attempts = <Duration>[];
  var completed = 0;

  Future<void> pass(
    List<EvalQuery> queries, {
    bool measureAdvanced = false,
  }) async {
    for (final q in queries) {
      final count = log.samples.length;
      final watch = Stopwatch()..start();
      await search.submit(q.text);
      if (measureAdvanced) {
        attempts.add(watch.elapsed);
        if (log.samples.length > count &&
            search.lastQuery == q.text &&
            search.errors.isEmpty) {
          completed++;
        } else {
          failures.add(
            '${q.id}: ${search.errors.isEmpty ? 'no result' : search.errors.join(' ')}',
          );
        }
      } else if (!(adv?.isOn ?? false) && search.errors.isNotEmpty) {
        throw StateError(
          'Standard benchmark ${q.id}: ${search.errors.join(' ')}',
        );
      }
    }
  }

  await pass(queries);
  log.clear();
  for (var r = 0; r < reps; r++) {
    await pass(queries);
  }
  final standardSamples = [...log.samples];
  final standardResources = ResourceSnapshot.capture(services.dbPaths);
  var backend = 'not run';
  var advancedStatus = 'not requested';
  Duration? loadTime;
  ResourceSnapshot? loadedResources;
  if (advanced && adv != null) {
    final watch = Stopwatch()..start();
    try {
      if (await adv.requestEnable() && adv.isOn) {
        loadTime = watch.elapsed;
        backend = adv.runtime.backendLabel ?? 'unknown';
        loadedResources = ResourceSnapshot.capture(services.dbPaths);
        final subset = [
          for (final id in ['E01', 'E02', 'E07', 'E08']) evalQuery(id),
        ];
        await pass(subset);
        log.clear(); // Discard Advanced warm-up, retain measured Standard samples.
        for (final sample in standardSamples) {
          log.add(sample);
        }
        for (var r = 0; r < reps; r++) {
          await pass(subset, measureAdvanced: true);
        }
        advancedStatus = 'completed';
      } else {
        advancedStatus =
            'skipped: ${adv.error ?? 'Gemma is not installed or did not load'}';
      }
    } finally {
      await adv.disable();
    }
  } else if (advanced) {
    advancedStatus = 'skipped: no Advanced service';
  }
  final measuredSamples = [...log.samples];
  final resources = ResourceSnapshot.capture(services.dbPaths);
  await search.browse();
  log.clear(); // The final browse is not a measured query.
  for (final sample in measuredSamples) {
    log.add(sample);
  }
  const retrievalStages = [
    Stage.sqlFilter,
    Stage.retrieval,
    Stage.queryEmbedding,
    Stage.gate,
    Stage.rowFetch,
  ];
  final retrievalTimes = [
    for (final sample in standardSamples.where((s) => s.semantic))
      retrievalStages.fold(
        Duration.zero,
        (sum, stage) => sum + (sample.stages[stage] ?? Duration.zero),
      ),
  ];
  return [
    '## Benchmark: fixture ${services.fixtureSize}, $reps reps after warm-up',
    '',
    '- OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    '- Standard: ${queries.length} standalone queries per pass (memo edit and follow-ups excluded).',
    '- Advanced: E01, E02, E07, E08 per pass; $advancedStatus.',
    '- Gemma backend: $backend',
    if (loadTime != null)
      '- Gemma load: ${formatMs(loadTime)} ms (outside search timings).',
    '- Standard resources: ${standardResources.describe()}',
    if (loadedResources != null)
      '- Gemma loaded resources: ${loadedResources.describe()}',
    '- After unload resources: ${resources.describe()}',
    '',
    log.toMarkdown(),
    if (retrievalTimes.isNotEmpty)
      '- Semantic retrieval (plan → cards), n=${retrievalTimes.length}: '
          'p50 ${formatMs(percentile(retrievalTimes, 50))} / '
          'p95 ${formatMs(percentile(retrievalTimes, 95))} ms (sum per query, then percentile).',
    if (attempts.isNotEmpty) ...[
      '',
      '- Advanced attempts: ${attempts.length}; completed: $completed; rejected/failed: ${failures.length}',
      '- Advanced attempt latency (including rejection), p50 ${formatMs(percentile(attempts, 50))} / '
          'p95 ${formatMs(percentile(attempts, 95))} ms.',
      if (failures.isNotEmpty) ...[
        '',
        '### Rejected/failed Advanced attempts',
        for (final f in failures) '- $f',
      ],
    ],
  ].join('\n');
}
