import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/search/rules/date_rules.dart';
import 'package:flutter_rag/search/rules/text_spans.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

DateRange? range(String q) {
  final r = DateRules().apply(QueryText(q));
  return r.matches.isEmpty ? null : r.matches.first.range;
}

List<PlanNote> notes(String q) => DateRules().apply(QueryText(q)).notes;

void main() {
  test('last month is September 2026 with exact UTC bounds', () {
    expect(range('food payments last month'),
        DateRange(DateTime.utc(2026, 8, 31, 17), DateTime.utc(2026, 9, 30, 17)));
    expect(range('previous month'), bangkokMonth(2026, 9));
  });

  test('years', () {
    expect(range('transfers last year'), bangkokYear(2025));
    expect(range('this year'), bangkokYear(2026));
    expect(range('Sushiro in 2025'), bangkokYear(2025));
    expect(range('payments of 2025 baht'), isNull); // an amount, not a year
  });

  test('this month is October 2026 (the reference month)', () {
    expect(range('this month'), bangkokMonth(2026, 10));
  });

  test('specific days, including leap day', () {
    expect(range('What did I spend on 29 February 2024?'), bangkokDay(2024, 2, 29));
    expect(range('February 29th, 2024'), bangkokDay(2024, 2, 29));
    expect(range('2024-02-29'), bangkokDay(2024, 2, 29));
    expect(range('on 1 September 2026'), bangkokDay(2026, 9, 1));
    expect(range('2025-02-30'), isNull);
    expect(notes('2025-02-30').single.kind, PlanNoteKind.ambiguous);
  });

  test('month and year', () {
    expect(range('utility payments in September 2026'), bangkokMonth(2026, 9));
    expect(range('in march 2026'), bangkokMonth(2026, 3));
  });

  test('month ranges resolve missing years against the reference date', () {
    expect(range('between June and August'),
        DateRange(bangkokToUtc(2026, 6), bangkokToUtc(2026, 9)));
    expect(range('between November and February'),
        DateRange(bangkokToUtc(2025, 11), bangkokToUtc(2026, 3)));
    expect(range('from June to August 2025'),
        DateRange(bangkokToUtc(2025, 6), bangkokToUtc(2025, 9)));
    expect(notes('between June and August').single.kind, PlanNoteKind.assumption);
  });

  test('bare month names use the most recent occurrence and say so', () {
    expect(range('in September'), bangkokMonth(2026, 9));
    expect(range('in November'), bangkokMonth(2025, 11));
    expect(notes('in November').single.kind, PlanNoteKind.assumption);
  });

  test('rolling periods', () {
    expect(range('last 7 days'), DateRange(bangkokToUtc(2026, 9, 27), bangkokToUtc(2026, 10, 4)));
    expect(range('past 2 weeks'), DateRange(bangkokToUtc(2026, 9, 20), bangkokToUtc(2026, 10, 4)));
    expect(range('last 3 months'), DateRange(bangkokToUtc(2026, 7), bangkokToUtc(2026, 10)));
    expect(range('yesterday'), bangkokDay(2026, 10, 2));
    expect(range('today'), bangkokDay(2026, 10, 3));
  });

  test('7-11 is not a date', () {
    expect(range('Show my 7-11 payments'), isNull);
  });

  test('matched phrases are consumed', () {
    final text = QueryText('camping last month');
    DateRules().apply(text);
    expect(text.isFree(8, 18), isFalse);
    expect(text.isFree(0, 7), isTrue);
  });
}
