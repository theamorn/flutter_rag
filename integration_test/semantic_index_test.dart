import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, debugPrintSynchronously;
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/data/db/rag_source_store.dart';
import 'package:flutter_rag/data/db/seed.dart';
import 'package:flutter_rag/data/db/transaction_repository.dart';
import 'package:flutter_rag/perf/stage_timer.dart';
import 'package:flutter_rag/retrieval/index_manager.dart';
import 'package:flutter_rag/retrieval/rag_index.dart';
import 'package:flutter_rag/retrieval/semantic_retriever.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:path_provider/path_provider.dart';

/// Counts embeds so "restart reuses the index" is observable.
class CountingRag implements RagIndex {
  CountingRag(this.inner);

  final RagIndex inner;
  int embeds = 0;

  @override
  Future<RagAddResult> addDocument(String text, {required String name}) =>
      inner.addDocument(text, name: name);

  @override
  Future<void> removeSource(int sourceId) => inner.removeSource(sourceId);

  @override
  Future<List<RagSource>> listSources() => inner.listSources();

  @override
  Future<List<RagHit>> searchHybrid(String query,
          {required int topK,
          required List<int> sourceIds,
          required double vectorWeight,
          required double bm25Weight}) =>
      inner.searchHybrid(query,
          topK: topK, sourceIds: sourceIds, vectorWeight: vectorWeight, bm25Weight: bm25Weight);

  @override
  Future<Float32List> embed(String text) {
    embeds++;
    return inner.embed(text);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // debugPrint is throttled and can lose the last lines when the test ends.
  debugPrint = debugPrintSynchronously;

  testWidgets('index 300 rows, restart without re-embedding, memo refresh, allowlist',
      (tester) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/itest_txn_300.sqlite');
    if (file.existsSync()) file.deleteSync();
    final db = AppDatabase.open(file);
    final repo = TransactionRepository(db);
    await seedIfEmpty(db, repo, 300);
    final store = RagSourceStore(db);

    var rag = CountingRag(await MobileRagIndex.open(fixtureSize: 9300)); // test-only engine DB
    await MobileRag.instance.clearAllData();
    final sw = Stopwatch()..start();
    await IndexManager(repo: repo, store: store, rag: rag).ensureIndexed();
    debugPrint('SEMANTIC indexed 300 in ${sw.elapsedMilliseconds} ms, embeds=${rag.embeds}');
    expect(await store.count(), 300);
    expect((await MobileRag.instance.listSources()).length, 300);

    // Restart: dispose the engine, reopen, ensure again -> no embeds.
    await MobileRag.dispose();
    rag = CountingRag(await MobileRagIndex.open(fixtureSize: 9300));
    await IndexManager(repo: repo, store: store, rag: rag).ensureIndexed();
    expect(rag.embeds, 0);

    final retriever = SemanticRetriever(repo: repo, store: store, rag: rag,
        config: const RetrievalConfig(minCosine: -1, minCosineWithKeyword: -1)); // gate off
    final e02 = SearchPlan(
      dateRange: bangkokMonth(2026, 9),
      maxAmount: const AmountBound(300000, inclusive: false),
      excludeCategories: const {Category.food},
      transactionType: TransactionType.purchase,
      semanticQuery: 'camping',
    );
    final timer = StageTimer();
    final ranked = await retriever.retrieve(e02, timer);
    debugPrint('SEMANTIC E02 top5=${ranked.ids.take(5).toList()} timings=${timer.durations}');
    expect(ranked.ids.take(5), containsAll(['txn_a01', 'txn_a02', 'txn_a03']));

    // Memo edit: the old memo stops matching by keyword.
    final index = IndexManager(repo: repo, store: store, rag: rag);
    await repo.updateMemo('txn_a29', 'Snacks for the office');
    await index.refreshTransaction('txn_a29');
    final a29 = (await store.get('txn_a29'))!.sourceId;
    final hits = await rag.searchHybrid('housewarming',
        topK: 200, sourceIds: await store.sourceIdsFor(SearchPlan.empty),
        vectorWeight: 0.5, bm25Weight: 0.5);
    expect(hits.where((h) => h.sourceId == a29 && h.bm25Rank > 0), isEmpty);
    await repo.updateMemo('txn_a29', 'Groceries for the housewarming party');
    await index.refreshTransaction('txn_a29');

    await MobileRag.instance.clearAllData();
    await MobileRag.dispose();
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
