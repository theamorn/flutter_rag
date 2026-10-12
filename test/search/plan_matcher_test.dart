import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/data/fixture/authored.dart';
import 'package:flutter_rag/search/plan_matcher.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction a(String id) => kAuthoredTransactions.firstWhere((t) => t.id == 'txn_$id');

void main() {
  test('Bangkok month boundaries: a14 is September, a13 is August', () {
    final sep = SearchPlan(dateRange: bangkokMonth(2026, 9));
    expect(planMatches(sep, a('a14')), isTrue);
    expect(planMatches(sep, a('a13')), isFalse);
  });

  test('inclusive and exclusive amount bounds at THB 1,299.00', () {
    expect(planMatches(const SearchPlan(maxAmount: AmountBound(129900, inclusive: true)), a('a01')), isTrue);
    expect(planMatches(const SearchPlan(maxAmount: AmountBound(129900, inclusive: false)), a('a01')), isFalse);
    expect(planMatches(const SearchPlan(minAmount: AmountBound(129900, inclusive: true)), a('a01')), isTrue);
    expect(planMatches(const SearchPlan(minAmount: AmountBound(129900, inclusive: false)), a('a01')), isFalse);
  });

  test('included categories OR together; excluded categories always win', () {
    const plan = SearchPlan(includeCategories: {Category.food, Category.grocery});
    expect(planMatches(plan, a('a03')), isTrue); // grocery
    expect(planMatches(plan, a('a01')), isFalse); // travel
    expect(planMatches(const SearchPlan(excludeCategories: {Category.food}), a('a04')), isFalse);
  });

  test('shops and people form one OR-ed payee constraint', () {
    const plan = SearchPlan(shopNames: {'Trail Supply'}, personNames: {'Mom'});
    expect(planMatches(plan, a('a01')), isTrue);
    expect(planMatches(plan, a('a24')), isTrue);
    expect(planMatches(plan, a('a22')), isFalse); // Amorn
    final family = SearchPlan(personNames: kFamilyGroup.toSet(), transactionType: TransactionType.transfer);
    expect(planMatches(family, a('a22')), isTrue);
    expect(planMatches(family, a('a26')), isFalse); // Ploy
  });

  test('hasMemo true/false', () {
    expect(planMatches(const SearchPlan(hasMemo: true), a('a01')), isTrue);
    expect(planMatches(const SearchPlan(hasMemo: true), a('a28')), isFalse);
    expect(planMatches(const SearchPlan(hasMemo: false), a('a28')), isTrue);
  });

  test('semantic query, sort and limit are not hard filters', () {
    const plan = SearchPlan(semanticQuery: 'nothing like this', sort: SortOrder.amountAsc, limit: 1);
    expect(planMatches(plan, a('a01')), isTrue);
  });
}
