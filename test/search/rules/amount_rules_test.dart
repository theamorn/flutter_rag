import 'package:flutter_rag/search/rules/amount_rules.dart';
import 'package:flutter_rag/search/rules/text_spans.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

AmountParse parse(String q) => const AmountRules().apply(QueryText(q));

void main() {
  test('strict and inclusive upper bounds', () {
    expect(parse('under THB 3,000, excluding food').max, const AmountBound(300000, inclusive: false));
    expect(parse('at most 3,000 baht').max, const AmountBound(300000, inclusive: true));
    expect(parse('up to ฿500').max, const AmountBound(50000, inclusive: true));
  });

  test('strict and inclusive lower bounds', () {
    expect(parse('over 10,000').min, const AmountBound(1000000, inclusive: false));
    expect(parse('at least THB 1,000.50').min, const AmountBound(100050, inclusive: true));
  });

  test('between is inclusive at both ends and order-independent', () {
    final a = parse('between THB 1,000 and THB 1,300');
    expect(a.min, const AmountBound(100000, inclusive: true));
    expect(a.max, const AmountBound(130000, inclusive: true));
    final b = parse('between 1,300 and 1,000 baht');
    expect(b.min!.minor, 100000);
    expect(b.max!.minor, 130000);
  });

  test('exactly', () {
    final a = parse('exactly 1,299');
    expect(a.min, const AmountBound(129900, inclusive: true));
    expect(a.max, const AmountBound(129900, inclusive: true));
  });

  test('foreign currency is never a filter', () {
    final a = parse('over 100 dollars last year');
    expect(a.min, isNull);
    expect(a.notes.single.text, contains('Only THB'));
  });

  test('a bare THB amount is flagged, not filtered', () {
    final text = QueryText('Payments of 500 baht');
    final a = const AmountRules().apply(text);
    expect(a.min, isNull);
    expect(a.max, isNull);
    final flagged = const AmountRules().flagBareAmounts(text);
    expect(flagged.single.kind, PlanNoteKind.ambiguous);
    expect(flagged.single.text, contains('"500 baht"'));
    expect(text.isFree(12, 20), isFalse);
  });

  test('plain numbers without a currency are ignored', () {
    final text = QueryText('top 5 payments');
    expect(const AmountRules().apply(text).min, isNull);
    expect(const AmountRules().flagBareAmounts(text), isEmpty);
  });
}
