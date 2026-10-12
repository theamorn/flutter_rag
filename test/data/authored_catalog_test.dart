import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/data/fixture/authored.dart';
import 'package:flutter_rag/data/fixture/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('30 authored rows with stable ids, 22 with memos', () {
    expect(kAuthoredTransactions.map((t) => t.id).toList(),
        [for (var i = 1; i <= 30; i++) 'txn_a${i.toString().padLeft(2, '0')}']);
    expect(kAuthoredTransactions.where((t) => t.memo != null).length, 22);
  });

  test('authored rows respect the payee/type invariants', () {
    for (final t in kAuthoredTransactions) {
      expect((t.shopName == null) != (t.personName == null), isTrue, reason: t.id);
      expect(t.type == TransactionType.purchase, t.shopName != null, reason: t.id);
      expect(t.amountMinor, greaterThan(0));
    }
  });

  test('timezone boundary rows sit where the spec says', () {
    final a13 = kAuthoredTransactions.firstWhere((t) => t.id == 'txn_a13');
    final a14 = kAuthoredTransactions.firstWhere((t) => t.id == 'txn_a14');
    expect(bangkokMonth(2026, 8).contains(a13.occurredAt), isTrue);
    expect(a14.occurredAt, DateTime.utc(2026, 8, 31, 17, 20));
    expect(bangkokMonth(2026, 9).contains(a14.occurredAt), isTrue);
  });

  test('filler never uses scheduled or authored-only shops', () {
    final names = kFillerMerchants.map((m) => m.name).toSet();
    for (final reserved in [kSevenEleven, kSushiro, kTermsGames, kUniqlo, ...kAuthoredOnlyShops]) {
      expect(names, isNot(contains(reserved)));
    }
  });

  test('every category has memo templates and none uses a reserved term', () {
    expect(kMemoTemplates.keys.toSet(), Category.values.toSet());
    final all = [
      ...kMemoTemplates.values.expand((x) => x),
      ...kFamilyMemoTemplates.values.expand((x) => x),
      ...kFriendMemoTemplates.values.expand((x) => x),
      ...kTermsGamesMemos,
    ];
    for (final memo in all) {
      for (final term in kReservedMemoTerms) {
        expect(memo.toLowerCase().contains(term), isFalse, reason: '"$memo" contains "$term"');
      }
    }
  });
}
