import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/data/db/seed.dart';
import 'package:flutter_rag/data/db/transaction_repository.dart';
import 'package:flutter_rag/data/fixture/authored.dart';
import 'package:flutter_rag/data/fixture/fixture_generator.dart';
import 'package:flutter_rag/search/plan_matcher.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late TransactionRepository repo;
  late List<Transaction> full;

  setUpAll(() async {
    full = buildFixture(5500);
    db = AppDatabase.memory();
    repo = TransactionRepository(db);
    expect(await seedIfEmpty(db, repo, 5500), isTrue);
  });
  tearDownAll(() => db.close());

  test('seeding inserts every row once', () async {
    expect(await repo.count(), 5500);
    expect(await seedIfEmpty(db, repo, 5500), isFalse);
  });

  test('rows round-trip exactly', () async {
    for (final a in kAuthoredTransactions) {
      expect(await repo.getById(a.id), a);
    }
    expect(await repo.getById('nope'), isNull);
  });

  test('getByIds keeps the requested order and skips unknown ids', () async {
    final rows = await repo.getByIds(['txn_a03', 'nope', 'txn_a01']);
    expect(rows.map((t) => t.id), ['txn_a03', 'txn_a01']);
  });

  test('browse pages: newest first, stable, no overlap', () async {
    final first = await repo.page(SearchPlan.empty, offset: 0, limit: 100);
    final next = await repo.page(SearchPlan.empty, offset: 100, limit: 20);
    expect(first.length, 100);
    expect(next.length, 20);
    final ids = [...first, ...next].map((t) => t.id).toList();
    expect(ids.toSet().length, 120);
    final expected = [...full]..sort((a, b) {
        final c = b.occurredAt.compareTo(a.occurredAt);
        return c != 0 ? c : b.id.compareTo(a.id);
      });
    expect(ids, expected.take(120).map((t) => t.id).toList());
  });

  final plans = <String, SearchPlan>{
    'browse': SearchPlan.empty,
    'Sep 2026 food under 300': SearchPlan(
      dateRange: bangkokMonth(2026, 9),
      maxAmount: const AmountBound(30000, inclusive: false),
      includeCategories: const {Category.food},
    ),
    'between 1,000 and 1,299 inclusive': const SearchPlan(
      minAmount: AmountBound(100000, inclusive: true),
      maxAmount: AmountBound(129900, inclusive: true),
    ),
    'over 1,299 exclusive': const SearchPlan(minAmount: AmountBound(129900, inclusive: false)),
    'family transfers 2025': SearchPlan(
      personNames: kFamilyGroup.toSet(),
      transactionType: TransactionType.transfer,
      dateRange: bangkokYear(2025),
    ),
    '7-11 or Mom': const SearchPlan(shopNames: {'7-11'}, personNames: {'Mom'}),
    'not food/travel, with memo': const SearchPlan(
      excludeCategories: {Category.food, Category.travel},
      hasMemo: true,
    ),
    'transfers without memo': const SearchPlan(hasMemo: false, transactionType: TransactionType.transfer),
    'leap day': SearchPlan(dateRange: bangkokDay(2024, 2, 29)),
    'year 2022 (empty)': SearchPlan(dateRange: bangkokYear(2022)),
  };

  for (final entry in plans.entries) {
    test('SQL agrees with the oracle: ${entry.key}', () async {
      final plan = entry.value;
      final expected = full.where((t) => planMatches(plan, t)).toList();
      final rows = await repo.page(plan, offset: 0, limit: 10000);
      expect(rows.map((t) => t.id).toSet(), expected.map((t) => t.id).toSet());
      final summary = await repo.summarize(plan);
      expect(summary.count, expected.length);
      expect(summary.totalMinor, expected.fold<int>(0, (s, t) => s + t.amountMinor));
    });
  }

  test('Sep 2026 food under 300 includes a14 but not a13', () async {
    final ids = (await repo.page(plans['Sep 2026 food under 300']!, offset: 0, limit: 1000))
        .map((t) => t.id);
    expect(ids, contains('txn_a14'));
    expect(ids, isNot(contains('txn_a13')));
  });

  test('limit caps rows, pages and the summary', () async {
    const plan = SearchPlan(sort: SortOrder.amountDesc, limit: 5);
    final top = await repo.page(plan, offset: 0, limit: 100);
    expect(top.length, 5);
    for (var i = 1; i < top.length; i++) {
      expect(top[i - 1].amountMinor >= top[i].amountMinor, isTrue);
    }
    expect((await repo.page(plan, offset: 3, limit: 20)).length, 2);
    expect((await repo.page(plan, offset: 5, limit: 20)), isEmpty);
    final summary = await repo.summarize(plan);
    expect(summary.count, 5);
    expect(summary.totalMinor, top.fold<int>(0, (s, t) => s + t.amountMinor));
  });

  test('sumAmounts adds the given rows', () async {
    expect(await repo.sumAmounts(['txn_a01', 'txn_a02']), 129900 + 245000);
    expect(await repo.sumAmounts(const []), 0);
  });

  test('a blank memo is stored as null and leaves the has-memo set', () async {
    const withMemo = SearchPlan(hasMemo: true);
    final before = (await repo.summarize(withMemo)).count;
    final updated = await repo.updateMemo('txn_a29', '   ');
    expect(updated.memo, isNull);
    expect((await repo.getById('txn_a29'))!.memo, isNull);
    expect((await repo.summarize(withMemo)).count, before - 1);
    await repo.updateMemo('txn_a29', 'Groceries for the housewarming party');
    expect((await repo.summarize(withMemo)).count, before);
    expect(() => repo.updateMemo('nope', 'x'), throwsStateError);
  });

  test('distinct payee names come from the data', () async {
    expect(await repo.distinctShopNames(), containsAll(['7-11', 'Sushiro', 'TermsGames', 'Uniqlo', 'Big Mart']));
    expect(await repo.distinctPersonNames(), containsAll(['Mom', 'Dad', 'Kids', 'Amorn', 'Alex']));
  });
}
