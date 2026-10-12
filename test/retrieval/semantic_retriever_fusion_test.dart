import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/data/db/rag_source_store.dart';
import 'package:flutter_rag/data/db/seed.dart';
import 'package:flutter_rag/data/db/transaction_repository.dart';
import 'package:flutter_rag/perf/stage_timer.dart';
import 'package:flutter_rag/retrieval/rag_index.dart';
import 'package:flutter_rag/retrieval/semantic_retriever.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replays one engine answer: hits in the engine's own (RRF k = 60) order,
/// with the vector rank, keyword rank and gate cosine measured on the phone
/// (CPH2499, 5,500 rows, Task 25 fix). The query vector is (1, 0); each
/// stored vector is (cos, sin), so the gate sees exactly the phone cosine.
class _ReplayRag implements RagIndex {
  _ReplayRag(this.hits);

  final List<RagHit> hits;

  @override
  Future<List<RagHit>> searchHybrid(
    String query, {
    required int topK,
    required List<int> sourceIds,
    required double vectorWeight,
    required double bm25Weight,
  }) async =>
      hits;

  @override
  Future<Float32List> embed(String text) async => Float32List.fromList([1, 0]);

  @override
  Future<RagAddResult> addDocument(String text, {required String name}) =>
      throw UnimplementedError();

  @override
  Future<void> removeSource(int sourceId) => throw UnimplementedError();

  @override
  Future<List<RagSource>> listSources() => throw UnimplementedError();
}

typedef _Row = (String txn, int vectorRank, int bm25Rank, double cosine);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late TransactionRepository repo;
  late RagSourceStore store;
  late List<String> fillers;

  setUp(() async {
    db = AppDatabase.memory();
    repo = TransactionRepository(db);
    await seedIfEmpty(db, repo, 300);
    store = RagSourceStore(db);
    fillers = [
      for (final t in await repo.all())
        if (!t.id.startsWith('txn_a')) t.id,
    ];
  });
  tearDown(() => db.close());

  /// Maps the phone's rows onto this fixture (decoys `d1`, `d2`, ... become
  /// generated rows), stores their gate vectors and runs the retriever.
  Future<List<String>> replay(List<_Row> rows, RetrievalConfig config, String query) async {
    final hits = <RagHit>[];
    final idFor = <String, String>{};
    var nextFiller = 0;
    for (final (i, (txn, vr, br, cos)) in rows.indexed) {
      final id = txn.startsWith('d') ? fillers[nextFiller++] : txn;
      idFor[txn] = id;
      final sourceId = 1000 + i;
      await store.upsert(id, sourceId, 'doc $txn',
          Float32List.fromList([cos, math.sqrt(1 - cos * cos)]));
      double rrf(int r) => r == 0 ? 0 : 0.5 / (60 + r);
      hits.add(RagHit(sourceId: sourceId, score: rrf(vr) + rrf(br), vectorRank: vr, bm25Rank: br));
    }
    final retriever = SemanticRetriever(repo: repo, store: store, rag: _ReplayRag(hits), config: config);
    final ranked = await retriever.retrieve(SearchPlan(semanticQuery: query), StageTimer());
    final back = {for (final e in idFor.entries) e.value: e.key};
    return [for (final id in ranked.ids) back[id]!];
  }

  // E24 "Party supplies for the housewarming": eight "Snacks for the office
  // party" memos crowd the engine's top 9; txn_a29 is the only keyword match
  // on "housewarming" (bm25Rank 1) but vector rank 72.
  const e24 = <_Row>[
    ('d1', 5, 4, 0.2908), ('d2', 9, 9, 0.2799), ('d3', 14, 7, 0.2676),
    ('d4', 17, 8, 0.2650), ('d5', 25, 3, 0.2575), ('d6', 27, 5, 0.2571),
    ('d7', 41, 6, 0.2419), ('d8', 31, 13, 0.2526), ('d9', 60, 2, 0.2294),
    ('txn_a29', 72, 1, 0.2234), ('d10', 39, 16, 0.2418), ('d11', 59, 10, 0.2297),
  ];

  test('E24: the only "housewarming" match reaches the top 5', () async {
    final ids = await replay(e24, kRetrievalConfig, 'Party supplies for the housewarming');
    expect(ids.take(5), contains('txn_a29'));
  });

  test('E24 defect: the engine order (k = 60) leaves txn_a29 10th', () async {
    final engineOrder = RetrievalConfig(
      fusionK: 60,
      minCosine: kRetrievalConfig.minCosine,
      minCosineWithKeyword: kRetrievalConfig.minCosineWithKeyword,
    );
    final ids = await replay(e24, engineOrder, 'Party supplies for the housewarming');
    expect(ids.indexOf('txn_a29'), 9);
  });

  // E08 "helping with the house": txn_a24 is the best vector match, but its
  // only keyword is "the" (bm25Rank 24); "Lunch money for the kids" memos
  // match "the" too and tie at random, so the engine put it 5th or 6th.
  test('E08: both relevant family transfers are in the top 5', () async {
    const e08 = <_Row>[
      ('txn_a23', 2, 1, 0.2830), ('d1', 6, 3, 0.2003), ('txn_a22', 11, 2, 0.1969),
      ('d2', 3, 18, 0.2098), ('d3', 8, 13, 0.1987), ('txn_a24', 1, 24, 0.2838),
      ('d4', 7, 17, 0.1993), ('d5', 13, 11, 0.1953), ('d6', 27, 4, 0.1811),
      ('d7', 10, 20, 0.1968), ('d8', 15, 15, 0.1927), ('d9', 19, 12, 0.1887),
    ];
    final ids = await replay(e08, kRetrievalConfig, 'helping with the house');
    expect(ids.take(5), containsAll(['txn_a22', 'txn_a24']));
  });

  // E25 after the memo restore: "housewarming" has one keyword match,
  // txn_a29, whose cosine (0.183) sat below the old keyword floor (0.19).
  test('E25: the single keyword match survives the gate, near-misses do not', () async {
    const e25 = <_Row>[
      ('txn_a29', 6, 1, 0.1834), ('txn_a03', 1, 0, 0.2350), ('d1', 2, 0, 0.1969),
      ('txn_a26', 3, 0, 0.1868), ('txn_a09', 4, 0, 0.1862),
      ('d2', 7, 1, 0.1085), // "Car tyres"-like: keyword match, unrelated meaning
    ];
    final ids = await replay(e25, kRetrievalConfig, 'housewarming');
    expect(ids, ['txn_a29']);
  });
}
