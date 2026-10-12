import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/search/plan_validator.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final validator = PlanValidator(PayeeDirectory(
    shops: const ['7-11', 'Sushiro', 'Big Mart'],
    people: const ['Mom', 'Dad', 'Kids', 'Amorn', 'Alex'],
  ));

  List<String> errorsOf(SearchPlan p) => validator.validate(p).errors;

  test('a valid plan is canonicalised', () {
    final v = validator.validate(const SearchPlan(
      shopNames: {'7-Eleven'},
      personNames: {'mother'},
      semanticQuery: '  camping  ',
    ));
    expect(v.isValid, isTrue);
    expect(v.plan!.shopNames, {'7-11'});
    expect(v.plan!.personNames, {'Mom'});
    expect(v.plan!.semanticQuery, 'camping');
    expect(v.plan!.sort, SortOrder.relevance);
  });

  test('blank semantic text becomes null and relevance sort falls back to newest', () {
    final v = validator.validate(const SearchPlan(semanticQuery: '   ', sort: SortOrder.relevance));
    expect(v.plan!.semanticQuery, isNull);
    expect(v.plan!.sort, SortOrder.newest);
  });

  test('empty date range', () {
    final r = bangkokMonth(2026, 9);
    expect(errorsOf(SearchPlan(dateRange: DateRange(r.end, r.start))), ['The date range is empty.']);
  });

  test('impossible amounts', () {
    expect(errorsOf(const SearchPlan(
      minAmount: AmountBound(500000, inclusive: false),
      maxAmount: AmountBound(100000, inclusive: false),
    )), hasLength(1));
    expect(errorsOf(const SearchPlan(
      minAmount: AmountBound(100000, inclusive: true),
      maxAmount: AmountBound(100000, inclusive: false),
    )), hasLength(1));
    expect(errorsOf(const SearchPlan(
      minAmount: AmountBound(100000, inclusive: true),
      maxAmount: AmountBound(100000, inclusive: true),
    )), isEmpty);
  });

  test('category included and excluded', () {
    expect(errorsOf(const SearchPlan(
      includeCategories: {Category.food},
      excludeCategories: {Category.food},
    )), ['Food is both included and excluded.']);
  });

  test('unknown payees', () {
    expect(errorsOf(const SearchPlan(shopNames: {'Starbucks'})), ['Unknown shop "Starbucks".']);
    expect(errorsOf(const SearchPlan(personNames: {'Bob'})), ['Unknown person "Bob".']);
  });

  test('payee and type conflicts', () {
    expect(errorsOf(const SearchPlan(shopNames: {'7-11'}, transactionType: TransactionType.transfer)),
        ['Shops only receive purchases, not transfers.']);
    expect(errorsOf(const SearchPlan(personNames: {'Mom'}, transactionType: TransactionType.purchase)),
        ['People only receive transfers, not purchases.']);
  });

  test('limit range', () {
    expect(errorsOf(const SearchPlan(limit: 0)), hasLength(1));
    expect(errorsOf(const SearchPlan(limit: 201)), hasLength(1));
    expect(errorsOf(const SearchPlan(limit: 5)), isEmpty);
  });

  test('notes survive validation', () {
    const note = PlanNote(PlanNoteKind.ambiguous, 'Unclear amount');
    expect(validator.validate(const SearchPlan(notes: [note])).plan!.notes, [note]);
  });
}
