import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/data/db/rag_source_store.dart';
import 'package:flutter_rag/data/db/seed.dart';
import 'package:flutter_rag/data/db/transaction_repository.dart';
import 'package:flutter_rag/perf/stage_timer.dart';
import 'package:flutter_rag/retrieval/index_manager.dart';
import 'package:flutter_rag/retrieval/semantic_retriever.dart';
import 'package:flutter_rag/search/plan_matcher.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_rag_index.dart';

// Fake embeddings score differently from MiniLM; these thresholds suit the
// fake only. Real values come from Task 19.
const testConfig = RetrievalConfig(minCosine: 0.2, minCosineWithKeyword: 0.05);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late TransactionRepository repo;
  late RagSourceStore store;
  late FakeRagIndex rag;
  late SemanticRetriever retriever;

  setUp(() async {
    db = AppDatabase.memory();
    repo = TransactionRepository(db);
    await seedIfEmpty(db, repo, 300);
    store = RagSourceStore(db);
    rag = FakeRagIndex();
    await IndexManager(repo: repo, store: store, rag: rag).ensureIndexed();
    retriever = SemanticRetriever(repo: repo, store: store, rag: rag, config: testConfig);
  });
  tearDown(() => db.close());

  final e02 = SearchPlan(
    dateRange: bangkokMonth(2026, 9),
    maxAmount: const AmountBound(300000, inclusive: false),
    excludeCategories: const {Category.food},
    transactionType: TransactionType.purchase,
    semanticQuery: 'camping',
  );

  test('E02: memo matches inside the hard filters, nothing else', () async {
    final ranked = await retriever.retrieve(e02, StageTimer());
    expect(ranked.ids, containsAll(['txn_a01', 'txn_a02', 'txn_a03']));
    expect(ranked.ids, isNot(contains('txn_a04'))); // food
    expect(ranked.ids, isNot(contains('txn_a05'))); // THB 4,890
    expect(ranked.ids, isNot(contains('txn_a06'))); // August
    final rows = await repo.getByIds(ranked.ids);
    expect(rows.every((t) => planMatches(e02, t)), isTrue);
  });

  test('the allowlist sent to the engine is exactly the eligible indexed set', () async {
    await retriever.retrieve(e02, StageTimer());
    final expected = await store.sourceIdsFor(e02);
    expect(rag.searches.single.toSet(), expected.toSet());
  });

  test('a no-match query returns nothing (cosine gate)', () async {
    final ranked = await retriever.retrieve(
        const SearchPlan(semanticQuery: 'scuba diving lessons'), StageTimer());
    expect(ranked.ids, isEmpty);
    expect(ranked.gatedOut, greaterThan(0));
  });

  test('Review Focus 3: an empty eligible set never reaches the engine', () async {
    final ranked = await retriever.retrieve(
        SearchPlan(dateRange: bangkokYear(2022), semanticQuery: 'camping'), StageTimer());
    expect(ranked.ids, isEmpty);
    expect(rag.searches, isEmpty);
  });

  test('Review Focus 3: eligible but unindexed rows never widen the search', () async {
    await store.deleteSources((await store.all()).values.map((m) => m.sourceId).toList());
    final ranked = await retriever.retrieve(e02, StageTimer());
    expect(ranked.ids, isEmpty);
    expect(ranked.notIndexed, greaterThan(0));
    expect(rag.searches, isEmpty);
  });

  test('timings cover filtering, retrieval, embedding and the gate', () async {
    final timer = StageTimer();
    await retriever.retrieve(e02, timer);
    expect(timer.durations.keys,
        containsAll([Stage.sqlFilter, Stage.retrieval, Stage.queryEmbedding, Stage.gate]));
  });
}
