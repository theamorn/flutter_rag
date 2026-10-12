import 'dart:convert';

import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/data/fixture/authored.dart';
import 'package:flutter_rag/data/fixture/catalog.dart';
import 'package:flutter_rag/data/fixture/fixture_generator.dart';
import 'package:flutter_test/flutter_test.dart';

int dayIndex(Transaction t) {
  final w = toBangkokWallClock(t.occurredAt);
  return DateTime.utc(w.year, w.month, w.day)
      .difference(DateTime.utc(2023, 10, 1))
      .inDays;
}

int monthIndex(Transaction t) {
  final w = toBangkokWallClock(t.occurredAt);
  return (w.year - 2023) * 12 + w.month - 10;
}

void main() {
  late List<Transaction> full;
  setUpAll(() => full = FixtureGenerator().generateFull());

  test('5,500 rows with unique ids, sorted oldest first', () {
    expect(full.length, 5500);
    expect(full.map((t) => t.id).toSet().length, 5500);
    for (var i = 1; i < full.length; i++) {
      expect(full[i - 1].occurredAt.isAfter(full[i].occurredAt), isFalse);
    }
  });

  test('every day has 4-6 rows: 200 days of 4, 676 of 5, 220 of 6', () {
    final perDay = <int, int>{};
    for (final t in full) {
      perDay.update(dayIndex(t), (n) => n + 1, ifAbsent: () => 1);
    }
    expect(perDay.length, 1096);
    final histogram = <int, int>{};
    for (final n in perDay.values) {
      histogram.update(n, (c) => c + 1, ifAbsent: () => 1);
    }
    expect(histogram, {4: 200, 5: 676, 6: 220});
  });

  test('7-11: one per two-day window, 548 in total', () {
    final rows = full.where((t) => t.shopName == kSevenEleven).toList();
    expect(rows.length, 548);
    expect(rows.map((t) => dayIndex(t) ~/ 2).toSet().length, 548);
  });

  test('Sushiro: one per calendar month, 36 in total', () {
    final rows = full.where((t) => t.shopName == kSushiro).toList();
    expect(rows.length, 36);
    expect(rows.map(monthIndex).toSet().length, 36);
  });

  test('Uniqlo: one per two-month window, 18 in total', () {
    final rows = full.where((t) => t.shopName == kUniqlo).toList();
    expect(rows.length, 18);
    expect(rows.map((t) => monthIndex(t) ~/ 2).toSet().length, 18);
  });

  test('TermsGames: 1-3 top-ups every month (36-108)', () {
    final perMonth = <int, int>{};
    for (final t in full.where((t) => t.shopName == kTermsGames)) {
      perMonth.update(monthIndex(t), (n) => n + 1, ifAbsent: () => 1);
    }
    expect(perMonth.length, 36);
    expect(perMonth.values.every((n) => n >= 1 && n <= 3), isTrue);
  });

  test('family: Mom and Dad get a transfer every month', () {
    for (final who in ['Mom', 'Dad']) {
      final months = full
          .where((t) => t.personName == who && t.type == TransactionType.transfer)
          .map(monthIndex)
          .toSet();
      expect(months.length, 36, reason: who);
    }
  });

  test('payee/type invariants, positive THB amounts, dates in range', () {
    for (final t in full) {
      expect((t.shopName == null) != (t.personName == null), isTrue, reason: t.id);
      expect(t.type == TransactionType.purchase, t.shopName != null, reason: t.id);
      expect(t.amountMinor, greaterThan(0));
      expect(t.currency, 'THB');
      expect(t.occurredAt.isBefore(kDatasetStartUtc), isFalse, reason: t.id);
      expect(t.occurredAt.isBefore(kDatasetEndUtc), isTrue, reason: t.id);
    }
  });

  test('550 memos, 4,950 null, none blank', () {
    final memos = full.where((t) => t.memo != null).toList();
    expect(memos.length, 550);
    expect(full.length - memos.length, 4950);
    expect(memos.every((t) => t.memo!.trim().isNotEmpty), isTrue);
  });

  test('memos favour important payments over routine 7-11 visits', () {
    double share(bool Function(Transaction) where) {
      final rows = full.where(where).toList();
      return rows.where((t) => t.memo != null).length / rows.length;
    }

    final big = share((t) => t.amountMinor >= 500000);
    final routine = share((t) => t.shopName == kSevenEleven && t.amountMinor < 20000);
    expect(big, greaterThan(routine * 5));
  });

  test('authored rows are included verbatim', () {
    final byId = {for (final t in full) t.id: t};
    for (final a in kAuthoredTransactions) {
      expect(byId[a.id], a);
    }
  });

  test('generated memos avoid reserved terms; authored-only shops stay authored', () {
    final authoredIds = {for (final a in kAuthoredTransactions) a.id};
    for (final t in full.where((t) => !authoredIds.contains(t.id))) {
      expect(kAuthoredOnlyShops.contains(t.shopName), isFalse, reason: t.id);
      final memo = t.memo?.toLowerCase();
      if (memo == null) continue;
      for (final term in kReservedMemoTerms) {
        expect(memo.contains(term), isFalse, reason: '${t.id}: "$memo"');
      }
    }
  });

  test('deterministic for a seed; a different seed differs', () {
    String json(List<Transaction> rows) => jsonEncode([for (final t in rows) t.toJson()]);
    expect(json(FixtureGenerator().generateFull()), json(full));
    expect(json(FixtureGenerator(seed: 1).generateFull()), isNot(json(full)));
  });

  for (final size in [300, 3000]) {
    test('subsample $size: exact size, 10% memos, every authored row, ids from full', () {
      final small = buildFixture(size);
      final byId = {for (final t in full) t.id: t};
      expect(small.length, size);
      expect(small.where((t) => t.memo != null).length, size ~/ 10);
      for (final a in kAuthoredTransactions) {
        expect(small.any((t) => t.id == a.id), isTrue, reason: a.id);
      }
      for (final t in small) {
        expect(byId[t.id], t);
      }
    });
  }

  test('buildFixture(5500) is the full fixture; other sizes are rejected', () {
    expect(buildFixture(5500).length, 5500);
    expect(() => buildFixture(1000), throwsArgumentError);
  });
}
