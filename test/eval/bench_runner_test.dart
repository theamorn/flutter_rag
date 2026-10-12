import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/app_services.dart';
import 'package:flutter_rag/advanced/gemma_tool.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/dev/bench_runner.dart';
import 'package:flutter_rag/perf/stage_timer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gemma.dart';
import '../support/fake_rag_index.dart';

class _FoodGemma extends FakeGemmaRuntime {
  @override
  Future<Map<String, dynamic>> callTool({
    required String system,
    required String user,
    required ToolSpec tool,
    required Duration timeout,
  }) async {
    toolCalls++;
    if (user.contains('Show food payments under THB 300 last month')) {
      return {
        'date_from': '2026-09-01',
        'date_to': '2026-09-30',
        'amount_max': 300,
        'amount_max_inclusive': false,
        'include_categories': ['food'],
      };
    }
    return {};
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'benchmark discards warm-up and browse and keeps modes separate',
    () async {
      final runtime =
          FakeGemmaRuntime(); // Empty plans safely reject E01/E02/E07/E08.
      final services = await AppServices.open(
        AppDatabase.memory(),
        300,
        rag: FakeRagIndex(),
        installer: FakeGemmaInstaller()..installed = true,
        runtime: runtime,
      );
      addTearDown(services.dispose);
      await services.index!.ensureIndexed();
      await services.advanced!.requestEnable();
      // The benchmark must turn an already-enabled model off for Standard.
      final report = await runBenchmark(services, reps: 2, advanced: true);
      final standard = services.timingLog.samples
          .where((s) => !s.advanced)
          .toList();
      expect(standard, hasLength(60)); // 30 standalone queries, twice.
      expect(standard.every((s) => s.query.isNotEmpty), isTrue);
      expect(services.timingLog.samples.any((s) => s.advanced), isFalse);
      expect(
        report,
        contains('Advanced attempts: 8; completed: 0; rejected/failed: 8'),
      );
      expect(report, contains('Gemma backend: fake'));
      expect(report, contains('Semantic retrieval (plan → cards)'));
      expect(services.advanced!.isOn, isFalse);
      expect(
        runtime.toolCalls,
        12,
      ); // 4 warm-up + 8 measured; no Standard jobs.
      expect(services.search.pager.items, hasLength(100));
      expect(services.search.plan.hasSemanticIntent, isFalse);
      expect(standard.every((s) => s.stages.containsKey(Stage.total)), isTrue);
    },
  );

  test('nonpositive repetitions fail before doing work', () async {
    final services = await AppServices.open(AppDatabase.memory(), 300);
    addTearDown(services.dispose);
    expect(() => runBenchmark(services, reps: 0), throwsArgumentError);
    expect(services.timingLog.samples, isEmpty);
  });

  test(
    'successful Advanced stages exclude warm-up and unload browse',
    () async {
      final services = await AppServices.open(
        AppDatabase.memory(),
        300,
        rag: FakeRagIndex(),
        installer: FakeGemmaInstaller()..installed = true,
        runtime: _FoodGemma(),
      );
      addTearDown(services.dispose);
      await services.index!.ensureIndexed();
      final report = await runBenchmark(services, reps: 2, advanced: true);
      expect(services.timingLog.samples.where((s) => s.advanced), hasLength(2));
      expect(
        report,
        contains('Advanced attempts: 8; completed: 2; rejected/failed: 6'),
      );
      expect(report, contains('| Advanced exact | total | 2 |'));
      expect(services.advanced!.isOn, isFalse);
    },
  );
}
