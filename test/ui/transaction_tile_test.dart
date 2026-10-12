import 'package:flutter/material.dart';
import 'package:flutter_rag/data/fixture/authored.dart';
import 'package:flutter_rag/ui/transaction_tile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, String id) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TransactionTile(
            transaction: kAuthoredTransactions.firstWhere((t) => t.id == id),
            onTap: () {},
          ),
        ),
      ));

  testWidgets('shows payee, amount, category, Bangkok date and memo preview', (tester) async {
    await pump(tester, 'txn_a01');
    expect(find.text('Trail Supply'), findsOneWidget);
    expect(find.text('THB 1,299.00'), findsOneWidget);
    expect(find.text('Travel · 12 Sep 2026'), findsOneWidget);
    expect(find.text('Sleeping bag and headlamp for our weekend camping trip'), findsOneWidget);
  });

  testWidgets('no memo line when the memo is null', (tester) async {
    await pump(tester, 'txn_a14');
    expect(find.text('Food · 1 Sep 2026'), findsOneWidget);
    expect(find.byKey(const Key('tile-memo')), findsNothing);
  });
}
