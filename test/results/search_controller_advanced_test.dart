import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/app_services.dart';
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/perf/stage_timer.dart';
import 'package:flutter_rag/results/search_controller.dart';
import 'package:flutter_rag/retrieval/semantic_retriever.dart';
import '../support/fake_rag_index.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gemma.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppServices services;
  late FakeGemmaRuntime runtime;

  setUp(() async {
    runtime = FakeGemmaRuntime();
    services = await AppServices.open(
      AppDatabase.memory(),
      300,
      installer: FakeGemmaInstaller()..installed = true,
      runtime: runtime,
      useAdvancedPlanner: true,
    );
  });
  tearDown(() => services.dispose());

  test('useAdvancedPlanner: false updates list ASAP via rules+SQL+RAG even with advanced on, and Gemma runs only after the list', () async {
    final fastServices = await AppServices.open(
      AppDatabase.memory(),
      300,
      installer: FakeGemmaInstaller()..installed = true,
      runtime: runtime,
      useAdvancedPlanner: false,
    );
    addTearDown(fastServices.dispose);

    await fastServices.advanced!.requestEnable();
    expect(fastServices.search.useAdvancedPlanner, isFalse);

    // Search and refine update the list immediately without calling Gemma:
    await fastServices.search.submit('Show transfers to Mom');
    expect(fastServices.search.plan.personNames, {'Mom'});
    expect(fastServices.search.pager.items, isNotEmpty);
    expect(runtime.toolCalls, 0);

    await fastServices.search.refine('last year');
    expect(fastServices.search.plan.dateRange, bangkokYear(2025));
    expect(runtime.toolCalls, 0);

    // Gemma is only invoked AFTER the list is shown (e.g., draftTransfer):
    await fastServices.search.submit('Show transfers to Mom');
    final momTxn = fastServices.search.pager.items.first;
    runtime.nextArgs = {
      'source_txn_id': momTxn.id,
      'recipient': 'Mom',
      'new_memo': 'Rent for October',
    };
    await fastServices.search.draftTransfer();
    expect(runtime.toolCalls, 1);
    expect(fastServices.search.transferDraft?.sourceTxnId, momTxn.id);
    expect(fastServices.search.transferDraft?.newMemo, 'Rent for October');
  });

  test('default off: standard searches make zero Gemma calls', () async {
    await services.search.submit('Show transfers to Mom last year');
    await services.search.refine('go back one year');
    expect(runtime.toolCalls + runtime.generateCalls + runtime.loadCalls, 0);
    expect(services.advanced!.jobsStarted, 0);
  });

  test('advanced on: Gemma plans, rows come from SQLite', () async {
    await services.advanced!.requestEnable();
    runtime.nextArgs = {
      'people': ['Mom'],
      'transaction_type': 'transfer',
      'date_from': '2025-01-01',
      'date_to': '2025-12-31',
    };
    await services.search.submit('money I sent my mother last year');
    expect(services.search.plan.personNames, {'Mom'});
    expect(services.search.plan.dateRange, bangkokYear(2025));
    expect(services.search.pager.items.every((t) => t.personName == 'Mom'), isTrue);
  });

  test('advanced failure keeps the previous chips and shows a message', () async {
    await services.search.submit('Show transfers to Mom last year');
    await services.advanced!.requestEnable();
    runtime.nextArgs = {
      'exclude_categories': ['gadgets'],
    };
    await services.search.submit('something odd');
    expect(services.search.errors.single, contains('Unknown category'));
    expect(services.search.plan.personNames, {'Mom'});
    expect(services.search.busy, isFalse);
  });

  test('switching off mid-plan: no late plan, standard search works', () async {
    await services.advanced!.requestEnable();
    runtime
      ..hold = Completer<void>()
      ..nextArgs = {
        'shops': ['7-11'],
      };
    final pending = services.search.submit('my 7-11 runs');
    await Future<void>.delayed(Duration.zero);
    await services.advanced!.disable();
    await pending;
    expect(services.search.plan.shopNames, isEmpty);
    await services.search.submit('Show my 7-11 payments last month');
    expect(services.search.plan.shopNames, {'7-11'});
  });

  test('advanced follow-up merges a delta into the current plan', () async {
    await services.advanced!.requestEnable();
    runtime.nextArgs = {
      'people': ['Mom'],
      'date_from': '2025-01-01',
      'date_to': '2025-12-31',
    };
    await services.search.submit('transfers to Mom last year');
    runtime.nextArgs = {'date_from': '2024-01-01', 'date_to': '2024-12-31'};
    await services.search.refine('the year before instead');
    expect(services.search.plan.personNames, {'Mom'});
    expect(services.search.plan.dateRange, bangkokYear(2024));
  });
  test('off clears busy before slow cancellation; re-enable cannot apply old plan', () async {
    await services.search.submit('Show transfers to Mom last year');
    final previous = services.search.plan;
    final previousQuery = services.search.lastQuery;
    await services.advanced!.requestEnable();
    runtime
      ..ignoreCancel = true
      ..hold = Completer<void>()
      ..nextArgs = {
        'shops': ['7-11'],
      };
    final pending = services.search.submit('my 7-11 runs');
    await Future<void>.delayed(Duration.zero);
    final stopped = services.advanced!.disable();
    expect(services.search.busy, isFalse);
    expect(services.search.plan, previous);
    expect(services.search.lastQuery, previousQuery);
    await services.search.submit('Show my Sushiro payments last month');
    expect(services.search.plan.shopNames, {'Sushiro'});
    final enabling = services.advanced!.requestEnable();
    runtime.hold!.complete();
    await pending;
    await stopped;
    await enabling;
    expect(services.search.plan.shopNames, {'Sushiro'});
    expect(services.search.busy, isFalse);
  });

  for (final replacement in ['browse', 'chips', 'submit', 'refine']) {
    test('stale advanced response cannot replace $replacement', () async {
      await services.advanced!.requestEnable();
      runtime
        ..ignoreCancel = true
        ..hold = Completer<void>()
        ..nextArgs = {
          'shops': ['7-11'],
        };
      final pending = services.search.submit('old');
      await Future<void>.delayed(Duration.zero);
      Future<void>? next;
      switch (replacement) {
        case 'browse':
          await services.search.browse();
        case 'chips':
          await services.search.applyPlan(services.search.plan);
        case 'submit':
          next = services.search.submit('new');
        case 'refine':
          next = services.search.refine('new');
      }
      runtime.nextArgs = {
        'people': ['Mom'],
      };
      runtime.hold!.complete();
      await pending;
      await next;
      expect(services.search.plan.shopNames, isEmpty);
      expect(services.search.busy, isFalse);
    });
  }

  test('timings mark advanced planning and standard fallback correctly', () async {
    final samples = <TimingSample>[];
    final search = TransactionSearchController(
      repo: services.repo,
      engine: services.search.engine,
      validator: services.search.validator,
      interpreter: services.search.interpreter,
      refiner: services.search.refiner,
      advanced: services.advanced,
      useAdvancedPlanner: true,
      onTiming: samples.add,
    );
    addTearDown(search.dispose);
    await search.submit('Show my 7-11 payments last month');
    await services.advanced!.requestEnable();
    runtime.nextArgs = {
      'shops': ['7-11'],
    };
    await search.submit('my 7-11 runs');
    await search.refine('again');
    await services.advanced!.disable();
    await search.refine('last year');
    expect(samples.map((s) => s.advanced), [false, true, true, false]);
    expect(samples[1].stages.containsKey(Stage.interpret), isTrue);
  });
  test('advanced plans use allowlisted semantic retrieval and memo refresh', () async {
    final rag = FakeRagIndex();
    final semantic = await AppServices.open(AppDatabase.memory(), 300,
      installer: FakeGemmaInstaller()..installed = true, runtime: runtime, rag: rag,
      useAdvancedPlanner: true,
      retrievalConfig: const RetrievalConfig(minCosine: .2, minCosineWithKeyword: .05));
    addTearDown(semantic.dispose);
    await semantic.index!.ensureIndexed(); await semantic.advanced!.requestEnable();
    runtime.nextArgs = {'date_from': '2026-09-01', 'date_to': '2026-09-30',
      'amount_max': 3000, 'exclude_categories': ['food'], 'transaction_type': 'purchase', 'semantic_query': 'camping'};
    await semantic.search.submit('camping purchases last month under THB 3,000 excluding food');
    expect(semantic.search.pager.items.map((t) => t.id), containsAll(['txn_a01', 'txn_a02', 'txn_a03']));
    expect(semantic.search.summary!.isCandidateSet, isTrue);
    expect(rag.searches.every((ids) => ids.isNotEmpty), isTrue);
    final calls = runtime.toolCalls;
    await semantic.search.updateMemo('txn_a01', 'Equipment for hiking');
    expect((await semantic.store.get('txn_a01'))!.docText, startsWith('Memo: Equipment for hiking.'));
    expect(runtime.toolCalls, calls);
  });

  test('chip and memo rerun timing uses the current toggle without new Gemma plans', () async {
    final samples = <TimingSample>[];
    final search = TransactionSearchController(repo: services.repo, engine: services.search.engine,
      validator: services.search.validator, interpreter: services.search.interpreter,
      refiner: services.search.refiner, advanced: services.advanced, useAdvancedPlanner: true, onTiming: samples.add);
    addTearDown(search.dispose);
    await services.advanced!.requestEnable();
    runtime.nextArgs = {'shops': ['7-11']}; await search.submit('my 7-11 runs');
    await search.applyPlan(search.plan);
    await services.advanced!.disable();
    await search.updateMemo('txn_a01', 'Equipment');
    expect(samples.map((s) => s.advanced), [true, true, false]);
    expect(runtime.toolCalls, 1);
  });

  test('toggle off during a chip edit still lands the SQL result', () async {
    await services.advanced!.requestEnable();
    runtime.nextArgs = {'shops': ['7-11']};
    await services.search.submit('my 7-11 runs');
    expect(services.search.plan.shopNames, {'7-11'});
    final calls = runtime.toolCalls;
    final edit = services.search.applyPlan(
      services.search.plan.copyWith(shopNames: {'Sushiro'}),
    );
    await services.advanced!.disable();
    await edit;
    expect(services.search.plan.shopNames, {'Sushiro'});
    expect(services.search.busy, isFalse);
    expect(services.search.errors, isEmpty);
    expect(runtime.toolCalls, calls);
  });

  test('omitted E02 dates keep previous query, chips and rows with safe error', () async {
    await services.search.submit('Show my 7-11 payments last month');
    final previous = services.search.plan;
    final ids = services.search.pager.items.map((t) => t.id).toList();
    final previousQuery = services.search.lastQuery;
    await services.advanced!.requestEnable();
    runtime.nextArgs = {'amount_max': 3000, 'exclude_categories': ['food'],
      'transaction_type': 'purchase', 'semantic_query': 'camping'};
    await services.search.submit('camping purchases last month under THB 3,000 excluding food');
    expect(services.search.errors.single, contains('requested dates'));
    expect(services.search.plan, previous);
    expect(services.search.lastQuery, previousQuery);
    expect(services.search.pager.items.map((t) => t.id), ids);
    expect(services.search.busy, isFalse);
  });

}
