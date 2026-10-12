import 'package:flutter/material.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/data/fixture/authored.dart';
import 'package:flutter_rag/ui/slip_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction a(String id) => kAuthoredTransactions.firstWhere((t) => t.id == id);

Future<void> openSlip(WidgetTester tester, Transaction t,
    Future<Transaction> Function(String, String?) onSave) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showTransactionSlip(context, transaction: t, onSaveMemo: onSave),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows every field from the original record', (tester) async {
    await openSlip(tester, a('txn_a01'), (id, m) async => a(id).withMemo(m));
    expect(find.text('Demo transaction slip'), findsOneWidget);
    expect(find.text('Trail Supply'), findsOneWidget);
    expect(find.text('Purchase'), findsOneWidget);
    expect(find.text('12 Sep 2026, 14:20 (Bangkok)'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);
    expect(find.text('txn_a01'), findsOneWidget);
    expect(find.text('Card payment at Trail Supply'), findsOneWidget);
    expect(find.byKey(const Key('slip-memo')), findsOneWidget);
  });

  testWidgets('hides the memo field when the memo is null', (tester) async {
    await openSlip(tester, a('txn_a28'), (id, m) async => a(id).withMemo(m));
    expect(find.byKey(const Key('slip-memo')), findsNothing);
  });

  testWidgets('editing and clearing the memo goes through onSaveMemo', (tester) async {
    final saved = <String?>[];
    await openSlip(tester, a('txn_a29'), (id, m) async {
      saved.add(m);
      return a(id).withMemo(m);
    });
    await tester.tap(find.text('Edit memo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Snacks for the office');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Snacks for the office'), findsOneWidget);

    await tester.tap(find.text('Edit memo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('slip-memo')), findsNothing);
    expect(saved, ['Snacks for the office', '']);
  });
}
