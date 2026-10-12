import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/data/db/seed.dart';
import 'package:flutter_rag/data/db/transaction_repository.dart';
import 'package:flutter_rag/perf/stage_timer.dart';
import 'package:flutter_rag/results/result_source.dart';
import 'package:flutter_rag/results/result_pager.dart';
import 'package:flutter_rag/results/result_summary.dart';
import 'package:flutter_rag/results/search_controller.dart';
import 'package:flutter_rag/results/search_engine.dart';
import 'package:flutter_rag/search/plan_validator.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each run() waits until the test completes it.
class ControlledRunner implements SearchRunner {
  ControlledRunner(this.repo);

  final TransactionRepository repo;
  final pending = <(SearchPlan, Completer<SearchOutcome>)>[];

  @override
  Future<SearchOutcome> run(SearchPlan plan, StageTimer timer) {
    final c = Completer<SearchOutcome>();
    pending.add((plan, c));
    return c.future;
  }

  void complete(int index) {
    final (plan, c) = pending[index];
    c.complete(
      SearchOutcome(
        plan: plan,
        source: ExactResultSource(repo, plan),
        summary: const ResultSummary.exact(
          count: 0,
          totalMinor: 0,
          totalLabel: 'x',
        ),
      ),
    );
  }
}

class _FailedPage implements ResultSource {
  @override
  Future<PageResult> fetch(int offset, int limit) async =>
      throw StateError('disk read failed');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late TransactionRepository repo;
  late PlanValidator validator;

  setUp(() async {
    db = AppDatabase.memory();
    repo = TransactionRepository(db);
    await seedIfEmpty(db, repo, 300);
    validator = PlanValidator(
      PayeeDirectory(
        shops: await repo.distinctShopNames(),
        people: await repo.distinctPersonNames(),
      ),
    );
  });
  tearDown(() => db.close());

  test('browse shows the newest 100 of all rows with an exact total', () async {
    final samples = <TimingSample>[];
    final c = TransactionSearchController(
      repo: repo,
      engine: SearchEngine(repo: repo),
      validator: validator,
      onTiming: samples.add,
    );
    await c.browse();
    expect(c.pager.items.length, 100);
    expect(c.summary!.countLabel, '300 transactions');
    expect(c.summary!.totalText, startsWith('Total outgoing payments THB '));
    expect(
      samples.single.stages.keys,
      containsAll([Stage.sqlFilter, Stage.rowFetch, Stage.total]),
    );
  });

  test(
    'a failed first page reports an error and emits no successful timing',
    () async {
      final runner = ControlledRunner(repo);
      final samples = <TimingSample>[];
      final c = TransactionSearchController(
        repo: repo,
        engine: runner,
        validator: validator,
        onTiming: samples.add,
      );
      addTearDown(c.dispose);
      final run = c.applyPlan(SearchPlan.empty);
      runner.pending.single.$2.complete(
        SearchOutcome(
          plan: SearchPlan.empty,
          source: _FailedPage(),
          summary: const ResultSummary.exact(
            count: 300,
            totalMinor: 0,
            totalLabel: 'x',
          ),
        ),
      );
      await run;
      expect(c.pager.status, PagerStatus.firstPageError);
      expect(samples, isEmpty);
      expect(c.errors.single, contains('disk read failed'));
      expect(c.busy, isFalse);
    },
  );

  test(
    'an invalid plan keeps the current chips and rows and shows errors',
    () async {
      final c = TransactionSearchController(
        repo: repo,
        engine: SearchEngine(repo: repo),
        validator: validator,
      );
      await c.applyPlan(const SearchPlan(shopNames: {'7-11'}));
      final rows = c.pager.items;
      await c.applyPlan(const SearchPlan(shopNames: {'Starbucks'}));
      expect(c.errors, ['Unknown shop "Starbucks".']);
      expect(c.plan.shopNames, {'7-11'});
      expect(c.pager.items, rows);
    },
  );

  test('Review Focus 1: a stale search never overwrites a newer one', () async {
    final runner = ControlledRunner(repo);
    final c = TransactionSearchController(
      repo: repo,
      engine: runner,
      validator: validator,
    );
    final first = c.applyPlan(const SearchPlan(shopNames: {'7-11'}));
    final second = c.applyPlan(const SearchPlan(personNames: {'Mom'}));
    runner.complete(1);
    await second;
    runner.complete(0);
    await first;
    expect(c.plan.personNames, {'Mom'});
    expect(c.plan.shopNames, isEmpty);
    expect(c.pager.items, isNotEmpty);
    expect(c.pager.items.every((t) => t.personName == 'Mom'), isTrue);
    expect(c.busy, isFalse);
  });

  test('an invalid plan submitted while a search is in flight leaves the controller idle', () async {
    final runner = ControlledRunner(repo);
    final c = TransactionSearchController(
      repo: repo,
      engine: runner,
      validator: validator,
    );
    final first = c.applyPlan(const SearchPlan(shopNames: {'7-11'}));
    expect(c.busy, isTrue);
    await c.applyPlan(const SearchPlan(shopNames: {'Starbucks'}));
    runner.complete(0); // the older search lands late and is discarded
    await first;
    expect(c.errors, ['Unknown shop "Starbucks".']);
    expect(c.busy, isFalse);
    expect(c.plan, SearchPlan.empty);
  });

  test(
    'saving a memo reruns the current search and notifies the index hook',
    () async {
      final refreshed = <String>[];
      final c = TransactionSearchController(
        repo: repo,
        engine: SearchEngine(repo: repo),
        validator: validator,
        onMemoChanged: (id) async => refreshed.add(id),
      );
      await c.applyPlan(const SearchPlan(hasMemo: true));
      final before = c.summary!.count;
      final updated = await c.updateMemo('txn_a29', '   ');
      expect(updated.memo, isNull);
      expect(refreshed, ['txn_a29']);
      expect(c.summary!.count, before - 1);
      expect(c.pager.items.any((t) => t.id == 'txn_a29'), isFalse);
    },
  );

  test('purchases filter returns only shop rows', () async {
    final c = TransactionSearchController(
      repo: repo,
      engine: SearchEngine(repo: repo),
      validator: validator,
    );
    await c.applyPlan(
      const SearchPlan(transactionType: TransactionType.purchase),
    );
    expect(c.pager.items.every((t) => t.shopName != null), isTrue);
  });
}
