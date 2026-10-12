import 'package:flutter_rag/advanced/gemma_tool.dart';
import 'package:flutter_rag/advanced/plan_args.dart';
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

final dir = PayeeDirectory(
  shops: const ['7-11', 'Sushiro', 'TermsGames', 'Uniqlo', 'Big Mart'],
  people: const ['Mom', 'Dad', 'Kids', 'Amorn', 'Alex'],
);

final e02 = SearchPlan(
  dateRange: bangkokMonth(2026, 9),
  maxAmount: const AmountBound(300000, inclusive: false),
  excludeCategories: const {Category.food},
  transactionType: TransactionType.purchase,
  semanticQuery: 'camping',
);

void main() {
  test('tool categories are exactly the eight db values', () {
    expect(kToolCategories, Category.values.map((c) => c.dbValue).toList());
    final props = kSearchTool.parameters['properties'] as Map<String, dynamic>;
    expect(
      props.keys,
      containsAll([
        'date_from',
        'date_to',
        'amount_max',
        'exclude_categories',
        'semantic_query',
        'clear',
      ]),
    );
  });

  test(
    'initial arguments become a plan (inclusive Bangkok dates -> UTC range)',
    () {
      final c = planFromToolArgs({
        'date_from': '2026-09-01',
        'date_to': '2026-09-30',
        'amount_max': 3000,
        'amount_max_inclusive': false,
        'exclude_categories': ['food'],
        'transaction_type': 'purchase',
        'semantic_query': ' camping ',
      }, directory: dir);
      expect(c.errors, isEmpty);
      expect(c.plan, e02);
      expect(c.plan!.notes.single.text, contains('Gemma'));
    },
  );

  test('amounts accept decimals and inclusive flags default to strict', () {
    final c = planFromToolArgs({
      'amount_min': 1000.5,
      'amount_max': '1,300',
    }, directory: dir);
    expect(c.plan!.minAmount, const AmountBound(100050, inclusive: false));
    expect(c.plan!.maxAmount, const AmountBound(130000, inclusive: false));
  });

  test('follow-up deltas keep unchanged filters (E29)', () {
    final c = planFromToolArgs(
      {'date_from': '2025-08-01', 'date_to': '2025-09-30'},
      current: e02,
      directory: dir,
    );
    expect(
      c.plan,
      e02.copyWith(
        dateRange: DateRange(bangkokToUtc(2025, 8), bangkokToUtc(2025, 10)),
      ),
    );
  });

  test('clear removes filters', () {
    final c = planFromToolArgs(
      {
        'clear': ['amount', 'semantic'],
      },
      current: e02,
      directory: dir,
    );
    expect(c.plan!.maxAmount, isNull);
    expect(c.plan!.semanticQuery, isNull);
    expect(c.plan!.excludeCategories, {Category.food});
  });

  test('family means the four family members as transfers', () {
    final c = planFromToolArgs({
      'family': true,
      'has_memo': true,
    }, directory: dir);
    expect(c.plan!.personNames, kFamilyGroup.toSet());
    expect(c.plan!.transactionType, TransactionType.transfer);
    expect(c.plan!.hasMemo, isTrue);
  });

  test('aliases resolve; unknown values are errors, never guesses', () {
    expect(
      planFromToolArgs({
        'shops': ['7-Eleven'],
      }, directory: dir).plan!.shopNames,
      {'7-11'},
    );
    expect(
      planFromToolArgs({
        'date_from': '2025-02-30',
      }, directory: dir).errors.single,
      contains('not a real date'),
    );
    expect(
      planFromToolArgs({
        'exclude_categories': ['gadgets'],
      }, directory: dir).errors.single,
      contains('Unknown category'),
    );
    expect(
      planFromToolArgs({'amount_max': 'cheap'}, directory: dir).errors,
      isNotEmpty,
    );
    expect(
      planFromToolArgs({
        'shops': ['Starbucks'],
      }, directory: dir).errors.single,
      contains('Unknown shop'),
    );
    expect(
      planFromToolArgs({'transaction_type': 'refund'}, directory: dir).errors,
      isNotEmpty,
    );
    expect(
      planFromToolArgs({
        'clear': ['everything'],
      }, directory: dir).errors,
      isNotEmpty,
    );
  });

  test('planToToolArgs round-trips', () {
    final plans = [
      e02,
      SearchPlan(
        personNames: kFamilyGroup.toSet(),
        transactionType: TransactionType.transfer,
        hasMemo: true,
      ),
      const SearchPlan(
        minAmount: AmountBound(100000, inclusive: true),
        maxAmount: AmountBound(130000, inclusive: true),
        sort: SortOrder.amountDesc,
        limit: 5,
      ),
      SearchPlan(
        dateRange: bangkokDay(2024, 2, 29),
        shopNames: const {'Sushiro'},
      ),
    ];
    for (final p in plans) {
      expect(planFromToolArgs(planToToolArgs(p), directory: dir).plan, p);
    }
    expect(planToToolArgs(e02)['date_to'], '2026-09-30');
    expect(planToToolArgs(e02)['amount_max'], 3000);
    expect(
      planToToolArgs(
        const SearchPlan(minAmount: AmountBound(123, inclusive: true)),
      )['amount_min'],
      1.23,
    );
  });

  test('rejects malformed argument shapes and unknown keys', () {
    for (final args in <Map<String, dynamic>>[
      {'unexpected': 1},
      {'date_from': 123},
      {'amount_max': true},
      {'amount_min_inclusive': 'yes'},
      {'shops': 'Sushiro'},
      {
        'people': [42],
      },
      {'clear': 'dates'},
      {'family': 'true'},
      {'has_memo': 1},
      {'limit': true},
      {'sort': 3},
    ]) {
      final converted = planFromToolArgs(args, directory: dir);
      expect(converted.isValid, isFalse, reason: '$args');
      expect(converted.plan, isNull, reason: '$args');
      expect(converted.errors, isNotEmpty, reason: '$args');
    }
  });

  test('amounts preserve exact satang and reject excess precision', () {
    final c = planFromToolArgs({
      'amount_min': '0.29',
      'amount_max': 1.23,
    }, directory: dir);
    expect(c.plan!.minAmount!.minor, 29);
    expect(c.plan!.maxAmount!.minor, 123);
    expect(
      planFromToolArgs({'amount_max': '1.234'}, directory: dir).isValid,
      isFalse,
    );
    expect(
      planFromToolArgs({'amount_max': -1}, directory: dir).isValid,
      isFalse,
    );
    expect(
      planFromToolArgs({'amount_max': double.infinity}, directory: dir).isValid,
      isFalse,
    );
  });

  test('follow-up changes one payee kind without losing the other', () {
    const current = SearchPlan(shopNames: {'Sushiro'}, personNames: {'Mom'});
    final c = planFromToolArgs(
      {
        'shops': ['Uniqlo'],
      },
      current: current,
      directory: dir,
    );
    expect(c.plan!.shopNames, {'Uniqlo'});
    expect(c.plan!.personNames, {'Mom'});
  });

  test(
    'partial date changes keep the other endpoint and reject reversed ranges',
    () {
      final changed = planFromToolArgs(
        {'date_from': '2026-08-01'},
        current: e02,
        directory: dir,
      );
      expect(
        changed.plan!.dateRange,
        DateRange(bangkokToUtc(2026, 8), bangkokToUtc(2026, 10)),
      );
      expect(
        planFromToolArgs({
          'date_from': '2026-10-01',
          'date_to': '2026-09-30',
        }, directory: dir).isValid,
        isFalse,
      );
    },
  );

  test(
    'inclusive flag can change an existing amount without changing its value',
    () {
      final c = planFromToolArgs(
        {'amount_max_inclusive': true},
        current: e02,
        directory: dir,
      );
      expect(c.plan!.maxAmount, const AmountBound(300000, inclusive: true));
    },
  );

  test('amount deltas retain absent inclusive flags for both bounds', () {
    const current = SearchPlan(
      minAmount: AmountBound(10000, inclusive: true),
      maxAmount: AmountBound(20000, inclusive: true),
    );
    final changed = planFromToolArgs(
      {'amount_min': 110, 'amount_max': 190},
      current: current,
      directory: dir,
    );
    expect(changed.plan!.minAmount, const AmountBound(11000, inclusive: true));
    expect(changed.plan!.maxAmount, const AmountBound(19000, inclusive: true));
  });

  test('cleared amount replacement defaults inclusive flags to strict', () {
    const current = SearchPlan(
      minAmount: AmountBound(10000, inclusive: true),
      maxAmount: AmountBound(20000, inclusive: true),
    );
    final changed = planFromToolArgs(
      {
        'clear': ['amount'],
        'amount_min': 110,
        'amount_max': 190,
      },
      current: current,
      directory: dir,
    );
    expect(changed.plan!.minAmount, const AmountBound(11000, inclusive: false));
    expect(changed.plan!.maxAmount, const AmountBound(19000, inclusive: false));
  });

  test(
    'amount parsing rejects overflow and numbers that cannot round-trip',
    () {
      final wholeBaht = planFromToolArgs({
        'amount_max': '92,233,720,368,547,758.00',
      }, directory: dir);
      expect(wholeBaht.plan!.maxAmount!.minor, 9223372036854775800);
      expect(planToToolArgs(wholeBaht.plan!)['amount_max'], 92233720368547758);
      for (final input in [
        '92,233,720,368,547,758.07',
        '92,233,720,368,547,758.08',
        '999999999999999999999999999999999999999999999999',
      ]) {
        final invalid = planFromToolArgs({'amount_max': input}, directory: dir);
        expect(invalid.plan, isNull, reason: input);
        expect(invalid.errors, isNotEmpty, reason: input);
      }
    },
  );

  test('outgoing numeric amounts never silently lose satang', () {
    const ordinary = SearchPlan(
      maxAmount: AmountBound(123456789012, inclusive: true),
    );
    final encoded = planToToolArgs(ordinary);
    expect(planFromToolArgs(encoded, directory: dir).plan, ordinary);

    const huge = SearchPlan(
      maxAmount: AmountBound(9223372036854775807, inclusive: true),
    );
    expect(() => planToToolArgs(huge), throwsRangeError);
  });
}
