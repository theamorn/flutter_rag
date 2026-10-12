import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/data/db/seed.dart';
import 'package:flutter_rag/data/db/transaction_repository.dart';
import 'package:flutter_rag/data/fixture/fixture_generator.dart';
import 'package:flutter_rag/dev/eval_queries.dart';
import 'package:flutter_rag/search/plan_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final full = buildFixture(5500);
  late AppDatabase db;
  late TransactionRepository repo;
  setUpAll(() async {
    db = AppDatabase.memory();
    repo = TransactionRepository(db);
    await seedIfEmpty(db, repo, 5500);
  });
  tearDownAll(() => db.close());

  for (final q in kEvalQueries.where((q) => q.expected != null && !q.expected!.hasSemanticIntent)) {
    test('${q.id}: SQL = oracle, zero hard-filter violations', () async {
      final plan = q.expected!;
      final rows = await repo.page(plan, offset: 0, limit: 10000);
      expect(rows.every((t) => planMatches(plan, t)), isTrue);
      expect(rows.map((t) => t.id).toSet(),
          full.where((t) => planMatches(plan, t)).map((t) => t.id).toSet());
      if (q.kind == EvalKind.noMatch) expect(rows, isEmpty);
    });
  }
}
