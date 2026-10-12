import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/search/rules/rule_parser.dart';
import 'package:flutter_rag/search/rules/rule_refiner.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

final refiner = RuleRefiner(RuleParser(
    directory: PayeeDirectory(shops: const ['7-11'], people: const ['Mom'])));

final e02 = SearchPlan(
  dateRange: bangkokMonth(2026, 9),
  maxAmount: const AmountBound(300000, inclusive: false),
  excludeCategories: const {Category.food},
  transactionType: TransactionType.purchase,
  semanticQuery: 'camping',
);

void main() {
  test('E29: go back one year and include the month before', () {
    final plan = refiner.refine(e02,
        'Same purchases, but go back one year and include the month before it too');
    expect(plan, e02.copyWith(dateRange: DateRange(bangkokToUtc(2025, 8), bangkokToUtc(2025, 10))));
  });

  test('filter phrases replace or add to the current plan', () {
    expect(refiner.refine(e02, 'exclude travel too').excludeCategories, {Category.food, Category.travel});
    expect(refiner.refine(e02, 'only transfers').transactionType, TransactionType.transfer);
    expect(refiner.refine(e02, 'last year instead').dateRange, bangkokYear(2025));
    expect(refiner.refine(e02, 'under 1,000 baht').maxAmount, const AmountBound(100000, inclusive: false));
  });

  test('bare and explicit topic follow-ups replace semanticQuery', () {
    expect(refiner.refine(e02, 'sleeping bag'), e02.copyWith(semanticQuery: 'sleeping bag'));
    expect(refiner.refine(e02, 'for sleeping bag'), e02.copyWith(semanticQuery: 'sleeping bag'));
    expect(refiner.refine(e02, 'about tent'), e02.copyWith(semanticQuery: 'tent'));
  });

  test('unsupported follow-ups leave the plan and say why', () {
    final fancier = refiner.refine(e02, 'make it fancier');
    expect(fancier, e02);
    expect(fancier.notes.single.text, kStandardFollowUpUnsupported);

    final more = refiner.refine(e02, 'show me more');
    expect(more, e02);
    expect(more.notes.single.text, kStandardFollowUpUnsupported);
  });
}
