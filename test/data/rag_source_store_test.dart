import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/data/db/rag_source_store.dart';
import 'package:flutter_rag/data/db/seed.dart';
import 'package:flutter_rag/data/db/transaction_repository.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late RagSourceStore store;

  setUp(() async {
    db = AppDatabase.memory();
    await seedIfEmpty(db, TransactionRepository(db), 300);
    store = RagSourceStore(db);
    await store.upsert('txn_a01', 11, 'doc a01', Float32List.fromList([1, 0]));
    await store.upsert('txn_a03', 13, 'doc a03', Float32List.fromList([0, 1]));
    await store.upsert('txn_a04', 14, 'doc a04', Float32List.fromList([1, 1]));
  });
  tearDown(() => db.close());

  test('mappings round-trip', () async {
    expect(await store.count(), 3);
    expect((await store.get('txn_a01'))!.sourceId, 11);
    expect(await store.txnIdForSource(13), 'txn_a03');
    expect((await store.all()).keys.toSet(), {'txn_a01', 'txn_a03', 'txn_a04'});
    expect((await store.vectorsFor(['txn_a03']))['txn_a03'], Float32List.fromList([0, 1]));
  });

  test('sourceIdsFor applies hard filters to indexed rows only', () async {
    final ids = await store.sourceIdsFor(const SearchPlan(excludeCategories: {Category.food}));
    expect(ids.toSet(), {11, 13}); // a04 is food; unindexed rows never appear
    expect(await store.txnIdsForSources([13, 99]), {13: 'txn_a03'});
  });

  test('deletes', () async {
    await store.deleteSources([11, 13]);
    await store.deleteTxn('txn_a04');
    expect(await store.count(), 0);
  });
}
