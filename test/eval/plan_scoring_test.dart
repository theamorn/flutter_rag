import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/dev/plan_scoring.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

PlanFieldScore s(Map<PlanField, PlanFieldScore> m, PlanField f) => m[f]!;

void main() {
  test('identical plans score zero on every field', () {
    final plan = SearchPlan(
      dateRange: bangkokMonth(2026, 9),
      maxAmount: const AmountBound(30000, inclusive: false),
      includeCategories: const {Category.food},
      semanticQuery: 'camping',
      sort: SortOrder.relevance,
    );
    final score = scorePlan(plan, plan);
    expect(score.keys.toSet(), PlanField.values.toSet());
    expect(score.values.every((x) => x.isExact), isTrue);
    expect(describeScore(score), isEmpty);
  });

  test('missing = expected set and got not; extra = got set and expected not', () {
    final expected = SearchPlan(
      dateRange: bangkokMonth(2026, 9),
      transactionType: TransactionType.purchase,
    );
    const got = SearchPlan(hasMemo: true, shopNames: {'Uniqlo'});
    final score = scorePlan(expected, got);
    expect(s(score, PlanField.dates), const PlanFieldScore(missing: 1));
    expect(s(score, PlanField.transactionType), const PlanFieldScore(missing: 1));
    expect(s(score, PlanField.hasMemo), const PlanFieldScore(extra: 1));
    expect(s(score, PlanField.shops), const PlanFieldScore(extra: 1));
    expect(s(score, PlanField.people), const PlanFieldScore());
  });

  test('a different value counts once, as extra', () {
    final score = scorePlan(
      SearchPlan(dateRange: bangkokMonth(2026, 9), hasMemo: true),
      SearchPlan(dateRange: bangkokMonth(2026, 8), hasMemo: false),
    );
    expect(s(score, PlanField.dates), const PlanFieldScore(extra: 1));
    expect(s(score, PlanField.hasMemo), const PlanFieldScore(extra: 1));
  });

  test('sets are scored per element in both directions', () {
    final score = scorePlan(
      const SearchPlan(
        includeCategories: {Category.food, Category.grocery},
        excludeCategories: {Category.bill},
        personNames: {'Mom', 'Dad'},
      ),
      const SearchPlan(
        includeCategories: {Category.food, Category.travel, Category.utility},
        personNames: {'Mom'},
      ),
    );
    expect(s(score, PlanField.includeCategories), const PlanFieldScore(missing: 1, extra: 2));
    expect(s(score, PlanField.excludeCategories), const PlanFieldScore(missing: 1));
    expect(s(score, PlanField.people), const PlanFieldScore(missing: 1));
  });

  test('amount value and inclusivity are separate fields', () {
    final sameAmountOtherSide = scorePlan(
      const SearchPlan(maxAmount: AmountBound(300000, inclusive: false)),
      const SearchPlan(maxAmount: AmountBound(300000, inclusive: true)),
    );
    expect(s(sameAmountOtherSide, PlanField.maxAmount), const PlanFieldScore());
    expect(s(sameAmountOtherSide, PlanField.maxInclusive), const PlanFieldScore(extra: 1));

    final otherAmount = scorePlan(
      const SearchPlan(maxAmount: AmountBound(300000, inclusive: false)),
      const SearchPlan(maxAmount: AmountBound(200000, inclusive: true)),
    );
    expect(s(otherAmount, PlanField.maxAmount), const PlanFieldScore(extra: 1));
    // The inclusivity of a different amount is not double counted.
    expect(s(otherAmount, PlanField.maxInclusive), const PlanFieldScore());

    final dropped = scorePlan(
      const SearchPlan(minAmount: AmountBound(1000, inclusive: true)),
      SearchPlan.empty,
    );
    expect(s(dropped, PlanField.minAmount), const PlanFieldScore(missing: 1));
    expect(s(dropped, PlanField.minInclusive), const PlanFieldScore());
  });

  test('semantic text is compared trimmed and case-insensitively; sort and limit count', () {
    final same = scorePlan(
      const SearchPlan(semanticQuery: 'Camping'),
      const SearchPlan(semanticQuery: '  camping '),
    );
    expect(s(same, PlanField.semanticQuery), const PlanFieldScore());

    final diff = scorePlan(
      const SearchPlan(semanticQuery: 'camping', sort: SortOrder.relevance),
      const SearchPlan(semanticQuery: 'tent', sort: SortOrder.newest, limit: 5),
    );
    expect(s(diff, PlanField.semanticQuery), const PlanFieldScore(extra: 1));
    expect(s(diff, PlanField.sort), const PlanFieldScore(extra: 1));
    expect(s(diff, PlanField.limit), const PlanFieldScore(extra: 1));
    expect(describeScore(diff), contains('sort: extra 1'));
  });

  test('totals add up and render as a markdown table', () {
    final totals = <PlanField, PlanFieldScore>{};
    addScores(totals, scorePlan(SearchPlan(dateRange: bangkokMonth(2026, 9)), SearchPlan.empty));
    addScores(totals, scorePlan(SearchPlan.empty, const SearchPlan(hasMemo: true)));
    addScores(totals, scorePlan(SearchPlan(dateRange: bangkokMonth(2026, 9)), SearchPlan.empty));
    expect(totals[PlanField.dates], const PlanFieldScore(missing: 2));
    expect(totals[PlanField.hasMemo], const PlanFieldScore(extra: 1));

    final table = renderFieldTotals(totals, 3);
    expect(table, contains('| field | missing | extra |'));
    expect(table, contains('| dates | 2 | 0 |'));
    expect(table, contains('| has memo | 0 | 1 |'));
    expect(table, contains('Over 3 queries'));
    // header + separator + one row per field
    expect(table.split('\n').where((l) => l.startsWith('|')).length, 2 + PlanField.values.length);
  });

  test('advanced failure messages are sorted into rejected and errored', () {
    for (final m in [
      'Gemma returned filters the app cannot use: Unknown shop "X".',
      'Gemma did not preserve the requested dates. Try rephrasing, or turn Advanced reasoning off.',
      'Gemma did not preserve the requested THB amount limits. Try rephrasing.',
      'Only THB amounts are supported, but Gemma applied an amount limit.',
      'Gemma answered without filters. Try rephrasing, or turn Advanced reasoning off.',
    ]) {
      expect(classifyAdvancedFailure(m), AdvancedOutcome.rejected, reason: m);
    }
    for (final m in [
      'Gemma took longer than 20 s.',
      'Gemma could not complete the request: boom',
      'Search failed: boom',
      'Evaluation guard: no result after 60.0 s.',
    ]) {
      expect(classifyAdvancedFailure(m), AdvancedOutcome.errored, reason: m);
    }
  });
}
