import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/data/db/rag_source_store.dart';
import 'package:flutter_rag/data/db/seed.dart';
import 'package:flutter_rag/data/db/transaction_repository.dart';
import 'package:flutter_rag/retrieval/index_manager.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_rag_index.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late TransactionRepository repo;
  late RagSourceStore store;
  late FakeRagIndex rag;
  late IndexManager index;

  setUp(() async {
    db = AppDatabase.memory();
    repo = TransactionRepository(db);
    await seedIfEmpty(db, repo, 300);
    store = RagSourceStore(db);
    rag = FakeRagIndex();
    index = IndexManager(repo: repo, store: store, rag: rag);
  });
  tearDown(() => db.close());

  test('indexes every transaction once, each with its own source', () async {
    await index.ensureIndexed();
    expect(index.isReady, isTrue);
    expect(index.progress.value.done, 300);
    expect(await store.count(), 300);
    expect(rag.sources.length, 300);
    final mappings = await store.all();
    expect(mappings.values.map((m) => m.sourceId).toSet().length, 300);
  });

  test('indexes memo-bearing transactions before memo-less ones in occurred_at DESC order', () async {
    await index.ensureIndexed();
    final rows = await repo.all();
    final byId = {for (final t in rows) t.id: t};
    final indexedIds = [for (final s in rag.sources.values) s.$1];
    final indexedTxns = [for (final id in indexedIds) byId[id]!];

    final withMemo = [for (final t in rows) if (t.memo != null) t.id];
    final withoutMemo = [for (final t in rows) if (t.memo == null) t.id];
    expect(withMemo, isNotEmpty);
    expect(withoutMemo, isNotEmpty);
    expect(indexedIds, [...withMemo, ...withoutMemo]);

    final memoGroup = indexedTxns.take(withMemo.length).toList();
    expect(memoGroup.every((t) => t.memo != null), isTrue);
    for (var i = 1; i < memoGroup.length; i++) {
      expect(
        memoGroup[i - 1].occurredAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(memoGroup[i].occurredAt.millisecondsSinceEpoch),
      );
    }

    final noMemoGroup = indexedTxns.skip(withMemo.length).toList();
    expect(noMemoGroup.every((t) => t.memo == null), isTrue);
    for (var i = 1; i < noMemoGroup.length; i++) {
      expect(
        noMemoGroup[i - 1].occurredAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(noMemoGroup[i].occurredAt.millisecondsSinceEpoch),
      );
    }
  });

  test('a restart reuses the index: nothing is embedded again', () async {
    await index.ensureIndexed();
    final calls = rag.embedCalls;
    await IndexManager(repo: repo, store: store, rag: rag).ensureIndexed();
    expect(rag.embedCalls, calls);
  });

  test('reconcile removes orphan sources and re-adds unmapped rows', () async {
    await index.ensureIndexed();
    final a01 = (await store.get('txn_a01'))!;
    await store.deleteTxn('txn_a01'); // crash after addDocument, before upsert
    await rag.addDocument('stale text', name: 'txn_a02'); // orphan from an old run
    await IndexManager(repo: repo, store: store, rag: rag).ensureIndexed();
    expect(rag.sources.containsKey(a01.sourceId), isFalse);
    expect(rag.sources.values.where((s) => s.$1 == 'txn_a02').length, 1);
    expect(await store.count(), 300);
    expect(rag.sources.length, 300);
  });

  test('a duplicate answer from the engine is an indexing error', () async {
    rag.forceDuplicate.add('txn_a20'); // a20 is not the first row indexed
    await expectLater(index.ensureIndexed(), throwsA(isA<IndexingError>()));
    expect(index.progress.value.phase, IndexPhase.failed);
  });

  test('a resumed ingestion (isDuplicate with chunks) is accepted', () async {
    rag.forceResume.add('txn_a20');
    await index.ensureIndexed();
    expect(index.isReady, isTrue);
  });

  test('Review Focus 4: memo edits and clears refresh the index', () async {
    await index.ensureIndexed();
    await repo.updateMemo('txn_a29', 'Snacks for the office');
    await index.refreshTransaction('txn_a29');
    expect((await store.get('txn_a29'))!.docText, startsWith('Memo: Snacks for the office.'));
    final sources = await store.sourceIdsFor(SearchPlan.empty);
    final hits = await rag.searchHybrid('housewarming',
        topK: 200, sourceIds: sources, vectorWeight: 0.5, bm25Weight: 0.5);
    final a29 = (await store.get('txn_a29'))!.sourceId;
    expect(hits.where((h) => h.sourceId == a29 && h.bm25Rank > 0), isEmpty);

    await repo.updateMemo('txn_a29', '   ');
    await index.refreshTransaction('txn_a29');
    expect((await store.get('txn_a29'))!.docText.startsWith('Memo:'), isFalse);
  });

  test('refresh is a no-op when the document did not change', () async {
    await index.ensureIndexed();
    final calls = rag.embedCalls;
    await index.refreshTransaction('txn_a01');
    expect(rag.embedCalls, calls);
  });
}
