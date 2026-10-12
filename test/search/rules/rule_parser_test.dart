import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/search/entities.dart';
import 'package:flutter_rag/search/rules/rule_parser.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

final parser = RuleParser(
  directory: PayeeDirectory(
    shops: const ['7-11', 'Sushiro', 'TermsGames', 'Uniqlo', 'Big Mart', 'Trail Supply'],
    people: const ['Mom', 'Dad', 'Kids', 'Amorn', 'Alex', 'Ploy'],
  ),
);

void main() {
  test('E01 exact: food under THB 300 last month', () {
    expect(
      parser.parse('Show food payments under THB 300 last month'),
      SearchPlan(
        dateRange: bangkokMonth(2026, 9),
        maxAmount: const AmountBound(30000, inclusive: false),
        includeCategories: const {Category.food},
      ),
    );
  });

  test('E02 semantic: camping, last month, under 3,000, excluding food', () {
    final plan = parser.parse(
        'Find things I bought for camping last month, under THB 3,000, excluding food.');
    expect(
      plan,
      SearchPlan(
        dateRange: bangkokMonth(2026, 9),
        maxAmount: const AmountBound(300000, inclusive: false),
        excludeCategories: const {Category.food},
        transactionType: TransactionType.purchase,
        semanticQuery: 'camping',
      ),
    );
    expect(plan.notes, contains(const PlanNote(PlanNoteKind.assumption, 'Searching by meaning: "camping"')));
  });

  test('E08 family transfers whose memos mention the house', () {
    expect(
      parser.parse('Find family transfers whose memos mention helping with the house'),
      SearchPlan(
        personNames: kFamilyGroup.toSet(),
        transactionType: TransactionType.transfer,
        hasMemo: true,
        semanticQuery: 'helping with the house',
      ),
    );
  });

  test('Review Focus 2: an ML Kit date over "7-11" never becomes a filter', () {
    const q = 'Show my 7-11 payments last month';
    final plan = parser.parse(q, entities: [
      ExtractedDate(8, 12, '7-11',
          instant: DateTime.utc(2026, 7, 10, 17), granularity: DateGranularity.day),
    ]);
    expect(plan, SearchPlan(shopNames: const {'7-11'}, dateRange: bangkokMonth(2026, 9)));
    expect(plan.notes, isEmpty);
  });

  test('aliases resolve to stored names', () {
    expect(parser.parse('Show my 7-Eleven payments').shopNames, {'7-11'});
    expect(parser.parse('top-ups at Terms Games').shopNames, {'TermsGames'});
    expect(parser.parse('money sent to mother').personNames, {'Mom'});
  });

  test('ML Kit fills a date the rules missed, and says so', () {
    const q = 'payments two weeks ago';
    final plan = parser.parse(q, entities: [
      ExtractedDate(9, 22, 'two weeks ago',
          instant: DateTime.utc(2026, 9, 19, 5), granularity: DateGranularity.week),
    ]);
    expect(plan.dateRange, DateRange(DateTime.utc(2026, 9, 18, 17), DateTime.utc(2026, 9, 25, 17)));
    expect(plan.notes.single.kind, PlanNoteKind.assumption);
    expect(plan.semanticQuery, isNull);
  });

  test('ML Kit money is noted, never filtered', () {
    const q = 'fifteen hundred baht at Sushiro';
    final plan = parser.parse(q, entities: [
      const ExtractedMoney(0, 20, 'fifteen hundred baht', minor: 150000, currency: 'baht'),
    ]);
    expect(plan.minAmount, isNull);
    expect(plan.maxAmount, isNull);
    expect(plan.notes.single.kind, PlanNoteKind.ambiguous);
    expect(plan.semanticQuery, isNull);
  });

  test('memo presence', () {
    expect(parser.parse('Transactions I added a memo to in 2024').hasMemo, isTrue);
    expect(parser.parse('Payments over THB 10,000 without a memo').hasMemo, isFalse);
    final both = parser.parse('payments with a memo and payments without a memo');
    expect(both.hasMemo, isNull);
    expect(both.notes.any((n) => n.kind == PlanNoteKind.ambiguous), isTrue);
  });

  test('sort and limit', () {
    final top = parser.parse('top 5 payments at Sushiro');
    expect(top.limit, 5);
    expect(top.sort, SortOrder.amountDesc);
    expect(parser.parse('oldest Uniqlo purchases').sort, SortOrder.oldest);
    expect(parser.parse('3 cheapest grocery payments').limit, 3);
  });

  test('category lists, negation and aliases', () {
    expect(parser.parse('excluding food and travel').excludeCategories, {Category.food, Category.travel});
    expect(parser.parse('groceries or clothes').includeCategories, {Category.grocery, Category.clothing});
    expect(parser.parse('Find my Sushiro meals in 2025').includeCategories, {Category.food});
    expect(parser.parse('personal care in 2025').includeCategories, {Category.personalCare});
  });

  test('both purchases and transfers -> no type, with a note', () {
    final plan = parser.parse('purchases and transfers last month');
    expect(plan.transactionType, isNull);
    expect(plan.notes.any((n) => n.kind == PlanNoteKind.ambiguous), isTrue);
  });

  test('meaning keeps the original casing and inner words', () {
    expect(parser.parse('Deposit for the apartment').semanticQuery, 'Deposit for the apartment');
    expect(parser.parse('Where did I buy a sleeping bag?').semanticQuery, 'sleeping bag');
    expect(parser.parse('How much did I top up at TermsGames last year?').semanticQuery, isNull);
  });

  test('deterministic', () {
    const q = 'Find the camping gear I bought in 2025';
    expect(parser.parse(q), parser.parse(q));
    expect(parser.parse(q).notes, parser.parse(q).notes);
  });
}
