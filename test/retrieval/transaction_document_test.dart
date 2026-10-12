import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/data/fixture/authored.dart';
import 'package:flutter_rag/data/fixture/fixture_generator.dart';
import 'package:flutter_rag/retrieval/transaction_document.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction a(String id) => kAuthoredTransactions.firstWhere((t) => t.id == id);

void main() {
  test('memo first, real fields only, unique Ref suffix', () {
    expect(
      transactionDocument(a('txn_a01')),
      'Memo: Sleeping bag and headlamp for our weekend camping trip. '
      'Purchase at Trail Supply. Category: Travel. '
      'Description: Card payment at Trail Supply. Date: 12 Sep 2026. '
      'Amount: THB 1,299.00. Ref txn_a01',
    );
  });

  test('absent memo and description are omitted, never "null"', () {
    final doc = transactionDocument(a('txn_a19'));
    expect(doc, 'Purchase at Big Mart. Category: Grocery. Date: 15 Jun 2026. Amount: THB 250.00. Ref txn_a19');
    expect(doc.contains('null'), isFalse);
  });

  test('transfers name the person', () {
    expect(transactionDocument(a('txn_a24')), startsWith('Memo: My share of September rent for the family home. Transfer to Mom.'));
  });

  test('long memos are clipped in the document (SQLite keeps the full memo)', () {
    final long = a('txn_a01').withMemo('x' * 500);
    expect(transactionDocument(long).length, lessThan(400));
  });

  test('every full-fixture document is unique and under 400 characters', () {
    final docs = buildFixture(5500).map(transactionDocument).toList();
    expect(docs.toSet().length, 5500);
    expect(docs.every((d) => d.length < 400), isTrue);
  });
}
