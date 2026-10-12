import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/data/db/seed.dart';
import 'package:flutter_rag/data/db/transaction_repository.dart';
import 'package:flutter_rag/perf/stage_timer.dart';
import 'package:flutter_rag/results/search_controller.dart';
import 'package:flutter_rag/results/search_engine.dart';
import 'package:flutter_rag/search/entities.dart';
import 'package:flutter_rag/search/plan_validator.dart';
import 'package:flutter_rag/search/rules/rule_parser.dart';
import 'package:flutter_rag/search/rules/rule_refiner.dart';
import 'package:flutter_rag/search/standard_interpreter.dart';
import 'package:flutter_test/flutter_test.dart';

/// The first extract() waits for [gate]; later ones return at once.
class SlowFirst implements EntitySource {
  final gate = Completer<void>();
  var calls = 0;

  @override
  Future<List<ExtractedEntity>> extract(String text) async {
    if (calls++ == 0) await gate.future;
    return const [];
  }

  @override
  Future<void> close() async {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late TransactionRepository repo;
  late PayeeDirectory dir;

  setUp(() async {
    db = AppDatabase.memory();
    repo = TransactionRepository(db);
    await seedIfEmpty(db, repo, 300);
    dir = PayeeDirectory(shops: await repo.distinctShopNames(), people: await repo.distinctPersonNames());
  });
  tearDown(() => db.close());

  TransactionSearchController controller(EntitySource entities) {
    final parser = RuleParser(directory: dir);
    return TransactionSearchController(
      repo: repo,
      engine: SearchEngine(repo: repo),
      validator: PlanValidator(dir),
      interpreter: StandardInterpreter(entities: entities, parser: parser),
      refiner: RuleRefiner(parser),
    );
  }

  test('submit interprets, validates and runs the query', () async {
    final c = controller(const NoEntitySource());
    await c.submit('Show transfers to Mom last year');
    expect(c.plan.personNames, {'Mom'});
    expect(c.plan.dateRange, bangkokYear(2025));
    expect(c.summary!.totalText, startsWith('Total transferred to Mom'));
    expect(c.lastQuery, 'Show transfers to Mom last year');
    expect(c.lastTimings.keys, contains(Stage.interpret));
  });

  test('a slow earlier submit cannot overwrite a later one', () async {
    final slow = SlowFirst();
    final c = controller(slow);
    final first = c.submit('Show my 7-11 payments');
    await c.submit('Show transfers to Mom');
    slow.gate.complete();
    await first;
    expect(c.plan.personNames, {'Mom'});
    expect(c.plan.shopNames, isEmpty);
  });

  test('refine applies a rule-based follow-up to the current plan', () async {
    final c = controller(const NoEntitySource());
    await c.submit('Show transfers to Mom last year');
    await c.refine('go back one year');
    expect(c.plan.dateRange, bangkokYear(2024));
  });

  test('an empty query goes back to browsing', () async {
    final c = controller(const NoEntitySource());
    await c.submit('Show transfers to Mom');
    await c.submit('   ');
    expect(c.plan.hasHardFilters, isFalse);
    expect(c.summary!.count, 300);
  });
}
