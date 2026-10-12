import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final plan = SearchPlan(
    dateRange: bangkokMonth(2026, 9),
    maxAmount: const AmountBound(300000, inclusive: false),
    excludeCategories: const {Category.food},
    semanticQuery: 'camping',
    notes: const [PlanNote(PlanNoteKind.assumption, 'x')],
  );

  test('equality ignores notes', () {
    expect(plan, plan.copyWith(notes: const []));
    expect(plan.hashCode, plan.copyWith(notes: const []).hashCode);
  });

  test('copyWith keeps fields unless given; null clears nullable fields', () {
    expect(plan.copyWith().dateRange, bangkokMonth(2026, 9));
    expect(plan.copyWith(dateRange: null).dateRange, isNull);
    expect(plan.copyWith(semanticQuery: null).hasSemanticIntent, isFalse);
    expect(plan.copyWith(maxAmount: null).maxAmount, isNull);
  });

  test('hasHardFilters and hasSemanticIntent', () {
    expect(SearchPlan.empty.hasHardFilters, isFalse);
    expect(plan.hasHardFilters, isTrue);
    expect(plan.hasSemanticIntent, isTrue);
    expect(const SearchPlan(hasMemo: false).hasHardFilters, isTrue);
  });
}
