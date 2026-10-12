import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/advanced/gemma_runtime.dart';
import 'package:flutter_rag/advanced/gemma_tool.dart';
import 'package:flutter_rag/app_services.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/dev/eval_queries.dart';
import 'package:flutter_rag/dev/eval_runner.dart';
import 'package:flutter_rag/retrieval/semantic_retriever.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gemma.dart';
import '../support/fake_rag_index.dart';

// Fake embeddings score differently from MiniLM (see semantic_retriever_test).
const _fakeConfig = RetrievalConfig(minCosine: 0.2, minCosineWithKeyword: 0.05);

/// Different answer per query: a plan, a rejection, a timeout, a hang.
class _ScriptedGemma extends FakeGemmaRuntime {
  final Completer<void> hang = Completer<void>();

  @override
  Future<Map<String, dynamic>> callTool({
    required String system,
    required String user,
    required ToolSpec tool,
    required Duration timeout,
  }) async {
    toolCalls++;
    if (user.contains('Find my Uniqlo purchases')) {
      return {
        'shops': ['Uniqlo'],
        'transaction_type': 'purchase',
      };
    }
    if (user.contains('Where did I buy a sleeping bag?')) {
      // An invented memo filter: must show up as `extra` on has memo.
      return {'transaction_type': 'purchase', 'semantic_query': 'sleeping bag', 'has_memo': true};
    }
    if (user.contains('Camping purchases excluding travel')) {
      // Expected plan has semanticQuery 'Camping'; lowercase 'camping' must still match.
      return {
        'transaction_type': 'purchase',
        'exclude_categories': ['travel'],
        'semantic_query': 'camping',
      };
    }
    if (user.contains('Scuba diving lessons')) throw const GemmaTimeout(Duration(seconds: 20));
    if (user.contains('Deposit for the apartment')) {
      await hang.future; // released by cancel()
      throw const GemmaCancelled();
    }
    throw GemmaNoToolCall('I cannot do that');
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    if (!hang.isCompleted) hang.complete();
  }
}

class _CaseDiffGemma extends FakeGemmaRuntime {
  @override
  Future<Map<String, dynamic>> callTool({
    required String system,
    required String user,
    required ToolSpec tool,
    required Duration timeout,
  }) async {
    toolCalls++;
    if (user.contains('School fees for the kids')) {
      // Expected plan has semanticQuery: 'School fees'; differs only by letter case.
      return {
        'people': ['Kids'],
        'semantic_query': 'school fees',
      };
    }
    if (user.contains('Camping purchases excluding travel')) {
      // Expected plan has semanticQuery: 'Camping'; differs only by letter case.
      return {
        'transaction_type': 'purchase',
        'exclude_categories': ['travel'],
        'semantic_query': 'camping',
      };
    }
    throw GemmaNoToolCall('I cannot do that');
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('standard and advanced evaluation run against an in-memory app', () async {
    final installer = FakeGemmaInstaller()..installed = true;
    final runtime = _ScriptedGemma();
    final services = await AppServices.open(
      AppDatabase.memory(),
      5500,
      rag: FakeRagIndex(),
      installer: installer,
      runtime: runtime,
      retrievalConfig: _fakeConfig,
    );
    await services.index!.ensureIndexed();

    // Standard: exactly the brief's report, no model involved.
    final standard = await runEvaluation(services, advanced: false);
    expect(standard, startsWith('## Standard evaluation: fixture 5500'));
    for (final q in kEvalQueries) {
      expect(standard, contains('| ${q.id} | ${q.kind.name} |'));
    }
    expect(standard, contains('- plan accuracy: 31 / 31'));
    expect(standard, contains('- hard-filter violations: 0'));
    expect(standard, contains('- Gemma jobs started so far: 0'));
    expect(standard, isNot(contains('Advanced outcomes')));
    expect(runtime.toolCalls, 0);

    // Advanced: rejected, errored and hung queries are recorded, never thrown.
    expect(await services.advanced!.requestEnable(), isTrue);
    expect(services.advanced!.isOn, isTrue);
    final report = await runEvaluation(
      services,
      advanced: true,
      queryTimeout: const Duration(milliseconds: 400),
    );
    expect(report, startsWith('## Advanced evaluation: fixture 5500'));
    for (final q in kEvalQueries) {
      expect(report, contains('| ${q.id} |'));
    }
    expect(report, contains('### Advanced outcomes and planning latency'));
    expect(report, contains('### Advanced per-field plan scoring'));
    expect(report, contains('| field | missing | extra |'));
    // E06 returned the exact expected plan.
    expect(RegExp(r'\| E06 \| plan \| \d+ \| exact \|').hasMatch(report), isTrue, reason: report);
    // E28 returned semantic_query differing only by letter case ('camping' vs 'Camping').
    expect(report, contains('| E28 | semantic | yes |'));
    expect(RegExp(r'\| E28 \| plan \| \d+ \| exact \|').hasMatch(report), isTrue, reason: report);
    expect(report, contains('- plan accuracy: 2 / 3'));
    // E20: Gemma invented has_memo.
    expect(RegExp(r'\| E20 \| plan \| \d+ \| has memo: extra 1').hasMatch(report), isTrue,
        reason: report);
    expect(report, contains('| has memo | 0 | 1 |'));
    // E01: no tool call is a safe rejection; E26: model timeout is an error.
    expect(RegExp(r'\| E01 \| rejected \|').hasMatch(report), isTrue, reason: report);
    expect(RegExp(r'\| E26 \| errored \| \d+ \| Gemma took longer than 20 s').hasMatch(report),
        isTrue, reason: report);
    // E22 hung: the runner's guard fired, recorded it and carried on to E23+.
    expect(RegExp(r'\| E22 \| errored \| \d+ \| Evaluation guard').hasMatch(report), isTrue,
        reason: report);
    expect(report, contains('| E32 |'));
    // The run left the app idle and cleared.
    expect(services.search.busy, isFalse);
    await services.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('plan accuracy counts semanticQuery case differences as a match', () async {
    final installer = FakeGemmaInstaller()..installed = true;
    final runtime = _CaseDiffGemma();
    final services = await AppServices.open(
      AppDatabase.memory(),
      300,
      rag: FakeRagIndex(),
      installer: installer,
      runtime: runtime,
      retrievalConfig: _fakeConfig,
    );
    await services.index!.ensureIndexed();
    expect(await services.advanced!.requestEnable(), isTrue);

    final report = await runEvaluation(services, advanced: true);
    expect(report, contains('| E23 | semantic | yes |'));
    expect(report, contains('| E28 | semantic | yes |'));
    expect(report, contains('- plan accuracy: 2 / 2'));
    expect(report, isNot(contains('E23 plan:')));
    expect(report, isNot(contains('E28 plan:')));
    await services.dispose();
  });
}
