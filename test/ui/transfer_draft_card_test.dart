import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_rag/advanced/transfer_drafter.dart';
import 'package:flutter_rag/app_services.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/data/fixture/authored.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_rag/ui/search_screen.dart';
import 'package:flutter_rag/ui/transfer_draft_card.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gemma.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final momRent = kAuthoredTransactions.firstWhere((t) => t.id == 'txn_a24');

  testWidgets('TransferDraftCard shows verified recipient, SQLite amount, memo, source chip, and confirms', (
    tester,
  ) async {
    final opened = <String>[];
    var dismissed = false;
    final draft = validateTransferDraft(
      {
        'source_txn_id': 'txn_a24',
        'recipient': 'Mom',
        'new_memo': 'My share of October rent for the family home',
      },
      [momRent],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransferDraftCard(
            draft: draft,
            onOpen: opened.add,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(find.text('Send THB 10,000.00 to Mom'), findsOneWidget);
    expect(
      find.text('New memo: "My share of October rent for the family home"'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ActionChip, 'txn_a24'));
    expect(opened, ['txn_a24']);

    await tester.tap(find.byKey(const ValueKey('confirm-transfer-draft')));
    await tester.pump();
    expect(dismissed, isTrue);
    expect(
      find.textContaining('Demo transfer confirmed: THB 10,000.00 to Mom'),
      findsOneWidget,
    );
  });

  testWidgets('Draft transfer button appears on SearchScreen for transfer rows and opens JSON popup dialog', (
    tester,
  ) async {
    final runtime = FakeGemmaRuntime();
    final services = (await tester.runAsync(
      () => AppServices.open(
        AppDatabase.memory(),
        300,
        installer: FakeGemmaInstaller()..installed = true,
        runtime: runtime,
      ),
    ))!;
    addTearDown(() => tester.runAsync(services.dispose));

    await tester.runAsync(() async {
      await services.search.applyPlan(const SearchPlan(personNames: {'Mom'}));
      await services.advanced!.requestEnable();
    });

    await tester.pumpWidget(MaterialApp(home: SearchScreen(services: services)));
    await tester.pumpAndSettle();

    expect(find.text('Draft transfer'), findsOneWidget);
    final first = services.search.pager.items.first;
    runtime.nextArgs = {
      'source_txn_id': first.id,
      'recipient': 'Mom',
      'new_memo': 'My share of October rent for the family home',
    };

    await tester.ensureVisible(find.text('Draft transfer'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Draft transfer'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    // Popup dialog automatically opens with both JSON blocks:
    expect(find.byKey(const ValueKey('transfer-draft-dialog')), findsOneWidget);
    expect(find.text('Draft Transfer JSON'), findsOneWidget);
    expect(find.text('1. Gemma Tool Call (draft_transfer)'), findsOneWidget);
    expect(find.text('2. Verified API Payload (Post-Hook Output)'), findsOneWidget);
    expect(find.textContaining('POST /v1/transfers/draft'), findsOneWidget);

    // Submitting from the dialog confirms and dismisses the draft:
    await tester.tap(find.byKey(const ValueKey('dialog-submit-transfer-api')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transfer-draft-dialog')), findsNothing);
    expect(services.search.transferDraft, isNull);
  });
}
