import 'dart:math' as math;

import '../../core/bangkok_time.dart';
import '../../core/categories.dart';
import '../../core/payees.dart';
import '../../core/transaction.dart';
import 'authored.dart';
import 'catalog.dart';
import 'day_book.dart';
import 'seeded_random.dart';

const int kFixtureSeed = 20261003;
const int kFullFixtureSize = 5500;
const List<int> kFixtureSizes = [300, 3000, 5500];
const int kFullFixtureMemoCount = 550;

/// A generated row before it gets a time, a memo and an ID.
class _Draft {
  _Draft({
    required this.seq,
    required this.day,
    this.shop,
    this.person,
    required this.category,
    required this.amountMinor,
    required this.description,
    required this.minHour,
    required this.maxHour,
    required this.memoPool,
  });

  final int seq;
  final int day;
  final String? shop;
  final String? person;
  final Category category;
  final int amountMinor;
  final String? description;
  final int minHour;
  final int maxHour;
  final List<String> memoPool;
  late DateTime occurredAt;
  String? memo;
}

/// Generates the full 5,500-row fixture (spec §6). Deterministic per [seed]:
/// every random draw comes from one [SeededRandom] stream in a fixed order.
class FixtureGenerator {
  FixtureGenerator({this.seed = kFixtureSeed});

  final int seed;

  late SeededRandom _rng;
  late DayBook _book;
  final List<_Draft> _drafts = [];

  List<Transaction> generateFull() {
    _rng = SeededRandom(seed);
    _book = DayBook(datasetDays(), dailyCapacities(_rng));
    _drafts.clear();

    // Stage 1: authored rows reserve their slots.
    for (final t in kAuthoredTransactions) {
      final w = toBangkokWallClock(t.occurredAt);
      _book.take(_book.indexOf(w.year, w.month, w.day));
    }
    _scheduledShops(); // stage 2
    _monthlyBills(); // stage 3
    _familyTransfers(); // stage 4
    _friendTransfers(); // stage 5
    _filler(); // stage 6
    _assignTimes(); // stage 7
    final authoredMemos =
        kAuthoredTransactions.where((t) => t.memo != null).length;
    _assignMemos(kFullFixtureMemoCount - authoredMemos); // stage 8

    // Stage 9: IDs in chronological order of the generated rows.
    _drafts.sort((a, b) {
      final c = a.occurredAt.compareTo(b.occurredAt);
      return c != 0 ? c : a.seq.compareTo(b.seq);
    });
    final generated = [
      for (var i = 0; i < _drafts.length; i++)
        _toTransaction(_drafts[i], 'txn_${(i + 1).toString().padLeft(4, '0')}'),
    ];
    return [...generated, ...kAuthoredTransactions]..sort(_chronological);
  }

  void _scheduledShops() {
    final dayCount = _book.days.length;
    // 7-11: one purchase on a random day of each two-day window -> 548.
    for (var from = 0; from < dayCount; from += 2) {
      _purchase(_book.pickDay(_rng, from, math.min(from + 2, dayCount)),
          kSevenElevenSpec, kMemoTemplates[Category.grocery]!);
    }
    final months = _book.monthWindows();
    for (final (from, to) in months) {
      // Sushiro: one per calendar month -> 36.
      _purchase(_book.pickDay(_rng, from, to), kSushiroSpec,
          kMemoTemplates[Category.food]!);
      // TermsGames: 1-3 top-ups on distinct days of the month.
      final count = _rng.intInRange(1, 3);
      final chosen = <int>{};
      while (chosen.length < count) {
        chosen.add(_book.pickDay(_rng, from, to));
      }
      for (final day in chosen) {
        final baht = _rng.pick(kTermsGamesDenominations);
        _purchase(day, kTermsGamesSpec, kTermsGamesMemos,
            amountMinor: baht * 100, description: 'TermsGames top-up');
      }
    }
    // Uniqlo: one per two-calendar-month window -> 18.
    for (var m = 0; m < months.length; m += 2) {
      _purchase(_book.pickDay(_rng, months[m].$1, months[m + 1].$2),
          kUniqloSpec, kMemoTemplates[Category.clothing]!);
    }
  }

  void _monthlyBills() {
    for (final (from, to) in _book.monthWindows()) {
      for (final bill in kMonthlyBills) {
        // Days 20-28 of the month.
        _purchase(_book.pickDay(_rng, from + 19, math.min(from + 28, to)), bill,
            kMemoTemplates[bill.category]!);
      }
    }
  }

  void _familyTransfers() {
    final months = _book.monthWindows();
    for (var m = 0; m < months.length; m++) {
      final (from, to) = months[m];
      _transfer(_book.pickDay(_rng, from, from + 5), 'Mom', Category.bill,
          _rng.intInRange(80, 120) * 10000); // THB 8,000-12,000 in hundreds
      _transfer(_book.pickDay(_rng, from + 9, from + 20), 'Dad',
          Category.utility, _rng.intInRange(1200, 3500) * 100);
      for (var k = 0; k < 2; k++) {
        _transfer(_book.pickDay(_rng, from, to), 'Kids', Category.food,
            _rng.intInRange(500, 2000) * 100);
      }
      if (m.isEven) {
        _transfer(
            _book.pickDay(_rng, from, to),
            'Amorn',
            _rng.chance(0.5) ? Category.grocery : Category.entertainment,
            _rng.intInRange(400, 3000) * 100);
      }
      if (_rng.chance(0.5)) {
        final who = _rng.pick(kFamilyGroup);
        final (category, min, max) = switch (who) {
          'Mom' => (Category.bill, 1000, 5000),
          'Dad' => (Category.utility, 500, 2000),
          'Kids' => (Category.food, 300, 1500),
          _ => (Category.grocery, 300, 2000),
        };
        _transfer(_book.pickDay(_rng, from, to), who, category,
            _rng.intInRange(min, max) * 100);
      }
    }
  }

  void _friendTransfers() {
    const categories = [
      Category.food, Category.food, Category.food,
      Category.travel, Category.entertainment,
    ];
    for (final (from, to) in _book.monthWindows()) {
      final count = _rng.intInRange(1, 3);
      for (var k = 0; k < count; k++) {
        _transfer(_book.pickDay(_rng, from, to), _rng.pick(kFriends),
            _rng.pick(categories), _rng.intInRange(150, 2500) * 100);
      }
    }
  }

  void _filler() {
    final weights = [for (final m in kFillerMerchants) m.weight];
    for (var day = 0; day < _book.days.length; day++) {
      while (_book.hasRoom(day)) {
        final spec = kFillerMerchants[_rng.pickWeighted(weights)];
        _purchase(day, spec, kMemoTemplates[spec.category]!);
      }
    }
  }

  void _assignTimes() {
    for (final d in _drafts) {
      final date = _book.days[d.day];
      final minute = _rng.intInRange(d.minHour * 60, d.maxHour * 60 + 59);
      d.occurredAt = bangkokToUtc(date.year, date.month, date.day)
          .add(Duration(minutes: minute));
    }
  }

  /// Weighted sampling without replacement (Efraimidis-Spirakis): the
  /// [count] drafts with the largest u^(1/w) get memos.
  void _assignMemos(int count) {
    final keyed = [
      for (final d in _drafts)
        (math.pow(_rng.nextDouble(), 1 / _memoWeight(d)).toDouble(), d),
    ]..sort((a, b) {
        final c = b.$1.compareTo(a.$1);
        return c != 0 ? c : a.$2.seq.compareTo(b.$2.seq);
      });
    for (final (_, d) in keyed.take(count)) {
      final friend =
          kFriends.contains(d.person) ? d.person! : _rng.pick(kFriends);
      d.memo = _rng.pick(d.memoPool).replaceAll('{friend}', friend);
    }
  }

  static double _memoWeight(_Draft d) {
    if (d.person != null && kFamilyGroup.contains(d.person)) return 3;
    if (d.amountMinor >= 500000) return 6;
    if (d.shop == kSevenEleven && d.amountMinor < 20000) return 0.1;
    if (d.amountMinor >= 100000) return 2;
    return 0.6;
  }

  void _purchase(int day, MerchantSpec spec, List<String> memoPool,
      {int? amountMinor, String? description}) {
    _book.take(day);
    final amount = amountMinor ?? _amount(spec);
    final desc = description ?? _purchaseDescription(spec.name);
    _drafts.add(_Draft(
      seq: _drafts.length,
      day: day,
      shop: spec.name,
      category: spec.category,
      amountMinor: amount,
      description: desc,
      minHour: spec.minHour,
      maxHour: spec.maxHour,
      memoPool: memoPool,
    ));
  }

  void _transfer(int day, String person, Category category, int amountMinor) {
    _book.take(day);
    _drafts.add(_Draft(
      seq: _drafts.length,
      day: day,
      person: person,
      category: category,
      amountMinor: amountMinor,
      description: _transferDescription(person),
      minHour: 7,
      maxHour: 22,
      memoPool: kFamilyMemoTemplates[person] ?? kFriendMemoTemplates[category]!,
    ));
  }

  int _amount(MerchantSpec spec) {
    final baht = _rng.intInRange(spec.minBaht, spec.maxBaht);
    final satang = spec.satang ? const [0, 25, 50, 75][_rng.nextInt(4)] : 0;
    return baht * 100 + satang;
  }

  String? _purchaseDescription(String shop) =>
      switch (_rng.pickWeighted(const [4.0, 3.0, 1.0, 2.0])) {
        0 => 'Card payment at $shop',
        1 => 'QR payment to $shop',
        2 => 'POS ${shop.toUpperCase()}',
        _ => null,
      };

  String? _transferDescription(String person) =>
      switch (_rng.pickWeighted(const [4.0, 1.0, 2.0])) {
        0 => 'PromptPay transfer to $person',
        1 => 'Bank transfer',
        _ => null,
      };

  static Transaction _toTransaction(_Draft d, String id) => Transaction(
        id: id,
        occurredAt: d.occurredAt,
        shopName: d.shop,
        personName: d.person,
        type: d.shop != null ? TransactionType.purchase : TransactionType.transfer,
        amountMinor: d.amountMinor,
        category: d.category,
        description: d.description,
        memo: d.memo,
      );
}

int _chronological(Transaction a, Transaction b) {
  final c = a.occurredAt.compareTo(b.occurredAt);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// The fixture for [size]: 300, 3,000 or 5,500. Smaller sizes are seeded
/// subsamples of the full fixture: every authored row, exactly 10% memos,
/// original IDs kept. Sorted oldest first.
List<Transaction> buildFixture(int size, {int seed = kFixtureSeed}) {
  if (!kFixtureSizes.contains(size)) {
    throw ArgumentError.value(size, 'size', 'use one of $kFixtureSizes');
  }
  final full = FixtureGenerator(seed: seed).generateFull();
  if (size == kFullFixtureSize) return full;

  final authoredIds = {for (final t in kAuthoredTransactions) t.id};
  final authored = full.where((t) => authoredIds.contains(t.id)).toList();
  final withMemo = full
      .where((t) => !authoredIds.contains(t.id) && t.memo != null)
      .toList();
  final noMemo = full
      .where((t) => !authoredIds.contains(t.id) && t.memo == null)
      .toList();
  final rng = SeededRandom(seed + size);
  rng.shuffle(withMemo);
  rng.shuffle(noMemo);
  final memoNeeded = size ~/ 10 - authored.where((t) => t.memo != null).length;
  final picked = [
    ...authored,
    ...withMemo.take(memoNeeded),
    ...noMemo.take(size - authored.length - memoNeeded),
  ];
  return picked..sort(_chronological);
}
