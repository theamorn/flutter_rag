import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/data/db/seed.dart';
import 'package:flutter_rag/data/db/transaction_repository.dart';
import 'package:flutter_rag/results/result_source.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late TransactionRepository repo;
  setUpAll(() async {
    db = AppDatabase.memory();
    repo = TransactionRepository(db);
    await seedIfEmpty(db, repo, 300);
  });
  tearDownAll(() => db.close());

  test('ranked source keeps rank order, re-checks hard filters, ends at the list end', () async {
    const plan = SearchPlan(hasMemo: true);
    final source = RankedResultSource(repo, plan, ['txn_a03', 'txn_a28', 'txn_a01']);
    final page = await source.fetch(0, 20);
    expect(page.rows.map((t) => t.id), ['txn_a03', 'txn_a01']); // a28 has no memo
    expect(page.reachedEnd, isTrue);
    expect((await source.fetch(3, 20)).rows, isEmpty);
  });

  test('exact source reports the end when a page comes back short', () async {
    final source = ExactResultSource(repo, SearchPlan.empty);
    expect((await source.fetch(0, 100)).reachedEnd, isFalse);
    expect((await source.fetch(290, 20)).reachedEnd, isTrue);
  });
}
