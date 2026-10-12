import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/data/db/rag_source_store.dart';
import 'package:flutter_rag/data/db/seed.dart';
import 'package:flutter_rag/data/db/transaction_repository.dart';
import 'package:flutter_rag/data/fixture/fixture_generator.dart';
import 'package:flutter_rag/retrieval/index_manager.dart';
import 'package:flutter_rag/retrieval/rag_index.dart';
import 'package:flutter_rag/retrieval/transaction_document.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_rag_index.dart';

/// Runs [onAdd] after each successful engine add (the worst moment to die:
/// the engine has the document, our mapping row is not written yet).
class HookedRag implements RagIndex {
  HookedRag(this.inner, {this.onAdd});

  final FakeRagIndex inner;
  final Future<void> Function(int addNumber)? onAdd;
  int adds = 0;

  @override
  Future<RagAddResult> addDocument(String text, {required String name}) async {
    final r = await inner.addDocument(text, name: name);
    await onAdd?.call(++adds);
    return r;
  }

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
  Future<Float32List> embed(String text) => inner.embed(text);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late TransactionRepository repo;
  late RagSourceStore store;
  late FakeRagIndex engine;

  setUp(() async {
    db = AppDatabase.memory();
    repo = TransactionRepository(db);
    await seedIfEmpty(db, repo, 300);
    store = RagSourceStore(db);
    engine = FakeRagIndex();
  });
  tearDown(() => db.close());

  test('a run killed part-way resumes and embeds only what is left', () async {
    final dying = HookedRag(engine, onAdd: (n) async {
      if (n == 120) throw StateError('process killed');
    });
    await expectLater(
        IndexManager(repo: repo, store: store, rag: dying).ensureIndexed(), throwsStateError);
    expect(await store.count(), 119); // the 120th was added but never mapped

    final before = engine.embedCalls;
    final restarted = IndexManager(repo: repo, store: store, rag: HookedRag(engine));
    await restarted.ensureIndexed();
    expect(restarted.isReady, isTrue);
    expect(engine.embedCalls - before, 181); // 300 - 119, not 300
    expect(await store.count(), 300);
    expect(engine.sources.length, 300); // the orphan was removed, not duplicated
  });

  test('rows added during a run are picked up by the next ensureIndexed', () async {
    final known = {for (final t in await repo.all()) t.id};
    final fresh = buildFixture(5500).where((t) => !known.contains(t.id)).take(5).toList();
    expect(fresh, hasLength(5));

    final rag = HookedRag(engine, onAdd: (n) async {
      if (n == 50) await repo.insertAll(fresh);
    });
    final index = IndexManager(repo: repo, store: store, rag: rag);
    await index.ensureIndexed();
    expect(await store.count(), 300); // this run works from its starting snapshot

    final before = engine.embedCalls;
    await index.ensureIndexed();
    expect(engine.embedCalls - before, 5); // only the new rows
    expect(await store.count(), 305);
  });

  test('a memo edited while indexing ends up indexed with the new memo', () async {
    final last = (await repo.all()).last; // still pending when the edit lands
    late final IndexManager index;
    final rag = HookedRag(engine, onAdd: (n) async {
      if (n == 10) {
        await repo.updateMemo(last.id, 'Edited while indexing');
        unawaited(index.refreshTransaction(last.id));
      }
    });
    index = IndexManager(repo: repo, store: store, rag: rag);
    await index.ensureIndexed();
    await index.refreshTransaction(last.id); // queued behind the run
    final current = (await repo.getById(last.id))!;
    expect((await store.get(last.id))!.docText, transactionDocument(current));
    expect(current.memo, 'Edited while indexing');
  });
}
