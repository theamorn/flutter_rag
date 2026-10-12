import 'package:flutter_rag/data/fixture/day_book.dart';
import 'package:flutter_rag/data/fixture/seeded_random.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('1,096 Bangkok days from 1 Oct 2023 to 30 Sep 2026', () {
    final days = datasetDays();
    expect(days.length, 1096);
    expect(days.first, DateTime.utc(2023, 10, 1));
    expect(days.last, DateTime.utc(2026, 9, 30));
    expect(days, contains(DateTime.utc(2024, 2, 29)));
  });

  test('capacities: 200 x 4, 676 x 5, 220 x 6 = 5,500', () {
    final caps = dailyCapacities(SeededRandom(1));
    expect(caps.length, 1096);
    expect(caps.fold<int>(0, (a, b) => a + b), 5500);
    expect(caps.where((c) => c == 4).length, 200);
    expect(caps.where((c) => c == 5).length, 676);
    expect(caps.where((c) => c == 6).length, 220);
  });

  test('indexOf and month windows', () {
    final book = DayBook(datasetDays(), List.filled(1096, 5));
    expect(book.indexOf(2024, 2, 29), 151);
    final months = book.monthWindows();
    expect(months.length, 36);
    expect(months.first, (0, 31));
    expect(months.last.$2, 1096);
    for (var i = 1; i < months.length; i++) {
      expect(months[i].$1, months[i - 1].$2);
    }
  });

  test('pickDay redraws inside the window when the first draw is full', () {
    final book = DayBook(datasetDays(), List.filled(1096, 1));
    for (var i = 0; i < 30; i++) {
      book.take(i); // fill days 0..29 of October 2023
    }
    expect(book.pickDay(SeededRandom(9), 0, 31), 30);
    book.take(30);
    expect(() => book.pickDay(SeededRandom(9), 0, 31), throwsStateError);
    expect(() => book.take(30), throwsStateError);
  });
}
