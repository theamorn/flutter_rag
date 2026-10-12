import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the reference time is 3 Oct 2026 12:00 in Bangkok', () {
    expect(kReferenceNow, DateTime.utc(2026, 10, 3, 5));
  });

  test('September 2026 in Bangkok is 31 Aug 17:00Z to 30 Sep 17:00Z', () {
    expect(
      bangkokMonth(2026, 9),
      DateRange(DateTime.utc(2026, 8, 31, 17), DateTime.utc(2026, 9, 30, 17)),
    );
  });

  test('December rolls over into January of the next year', () {
    expect(bangkokMonth(2026, 12).end, DateTime.utc(2026, 12, 31, 17));
    expect(bangkokYear(2025).end, DateTime.utc(2025, 12, 31, 17));
  });

  test('leap day 2024 is a full Bangkok day', () {
    final d = bangkokDay(2024, 2, 29);
    expect(d.end.difference(d.start), const Duration(days: 1));
    expect(d.end, bangkokToUtc(2024, 3, 1));
  });

  test('ranges include the start and exclude the end', () {
    final sep = bangkokMonth(2026, 9);
    expect(sep.contains(sep.start), isTrue);
    expect(sep.contains(sep.end), isFalse);
    expect(DateRange(sep.end, sep.end).isEmpty, isTrue);
  });

  test('00:20 on 1 Sep in Bangkok is still 31 Aug in UTC', () {
    final t = DateTime.utc(2026, 8, 31, 17, 20);
    expect(formatBangkokDateTime(t), '1 Sep 2026, 00:20');
    expect(formatBangkokIsoDate(t), '2026-09-01');
    expect(startOfBangkokDay(t), DateTime.utc(2026, 8, 31, 17));
    expect(bangkokMonth(2026, 9).contains(t), isTrue);
  });

  test('formatDateRange shows the last included day', () {
    expect(formatDateRange(bangkokMonth(2026, 9)), '1 Sep 2026 – 30 Sep 2026');
    expect(formatDateRange(bangkokDay(2024, 2, 29)), '29 Feb 2024');
  });
}
