import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = Transaction(
    id: 'txn_0127',
    occurredAt: DateTime.utc(2026, 9, 12, 7, 20),
    shopName: 'Trail Supply',
    type: TransactionType.purchase,
    amountMinor: 129900,
    category: Category.travel,
    description: 'Card payment at Trail Supply',
    memo: 'Sleeping bag and headlamp for our weekend camping trip',
  );

  test('JSON uses the spec field names and round-trips', () {
    final json = t.toJson();
    expect(json['occurred_at'], '2026-09-12T07:20:00.000Z');
    expect(json['transaction_type'], 'purchase');
    expect(json['person_name'], isNull);
    expect(Transaction.fromJson(json), t);
  });

  test('blank memos normalise to null', () {
    expect(normalizeMemo('   '), isNull);
    expect(normalizeMemo(''), isNull);
    expect(normalizeMemo(null), isNull);
    expect(normalizeMemo('  Deposit  '), 'Deposit');
    expect(t.withMemo('  ').memo, isNull);
    expect(t.withMemo('New').memo, 'New');
  });

  test('payeeName is the shop or the person', () {
    expect(t.payeeName, 'Trail Supply');
  });
}
