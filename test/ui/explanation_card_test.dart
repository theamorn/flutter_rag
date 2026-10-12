import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_rag/advanced/explainer.dart';
import 'package:flutter_rag/app_services.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_rag/ui/explanation_card.dart';
import 'package:flutter_rag/ui/search_screen.dart';
import 'package:flutter_rag/ui/transaction_tile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gemma.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<List<String>> pump(WidgetTester tester, Explanation e) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExplanationCard(explanation: e, onOpen: opened.add, onDismiss: () {}),
        ),
      ),
    );
    return opened;
  }

  testWidgets('shows the text and tappable citations', (tester) async {
    final opened = await pump(
      tester,
      validateExplanation('Camping gear [txn_a01] and a tent [txn_a02].', {'txn_a01', 'txn_a02'}),
    );
    expect(find.textContaining('Camping gear'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'txn_a02'));
    expect(opened, ['txn_a02']);
  });

  testWidgets('no valid citation -> explanation unavailable', (tester) async {
    await pump(tester, validateExplanation('You went camping.', {'txn_a01'}));
    expect(find.textContaining('Explanation unavailable'), findsOneWidget);
    expect(find.textContaining('You went camping'), findsNothing);
  });

  testWidgets('removed references are disclosed', (tester) async {
    await pump(tester, validateExplanation('[txn_a01] and [txn_9999]', {'txn_a01'}));
    expect(find.textContaining('Removed 1 reference'), findsOneWidget);
  });

  group('on the search screen', () {
    late FakeGemmaRuntime runtime;
    late AppServices services;

    // The model queue's futures belong to the real zone (they were created
    // under runAsync), so the press must run there too.
    Future<void> tapExplain(WidgetTester tester) async {
      // With the keyboard up the header scrolls, so bring the button into view.
      await tester.ensureVisible(find.text('Explain results'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Explain results'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }

    Future<void> open(
      WidgetTester tester, {
      Size size = const Size(360, 640),
      double keyboard = 0,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });
      runtime = FakeGemmaRuntime();
      services = (await tester.runAsync(
        () => AppServices.open(
          AppDatabase.memory(),
          300,
          installer: FakeGemmaInstaller()..installed = true,
          runtime: runtime,
        ),
      ))!;
      addTearDown(() => tester.runAsync(services.dispose));
      await tester.runAsync(() async {
        await services.search.applyPlan(const SearchPlan(personNames: {'Kids'}));
        await services.advanced!.requestEnable();
      });
      await tester.pumpWidget(MaterialApp(home: SearchScreen(services: services)));
      await tester.pumpAndSettle();
    }

    testWidgets('button appears only when Advanced is on; Explain, open source, dismiss', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Explain results'), findsOneWidget);
      final first = services.search.pager.items.first.id;
      runtime.nextText = 'Allowance for the kids [$first].';
      await tapExplain(tester);
      expect(find.textContaining('Allowance for the kids'), findsOneWidget);
      expect(find.byType(TransactionTile), findsWidgets); // rows stay visible

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(ActionChip, first));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Demo transaction slip'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Allowance for the kids'), findsNothing);

      await tester.runAsync(services.advanced!.disable);
      await tester.pumpAndSettle();
      expect(find.text('Explain results'), findsNothing);
    });

    testWidgets('compact phone with keyboard: long card scrolls, list stays reachable', (
      tester,
    ) async {
      await open(tester, keyboard: 300);
      final first = services.search.pager.items.first.id;
      runtime.nextText = List.filled(
        30,
        'A long sentence about the allowance and school fees [$first].',
      ).join(' ');
      await tapExplain(tester);
      expect(tester.takeException(), isNull);
      final card = find.byType(ExplanationCard);
      expect(card, findsOneWidget);
      // The new card scrolled itself into the capped header: its title and the
      // dismiss button are on screen above the keyboard.
      expect(find.byTooltip('Dismiss').hitTestable(), findsOneWidget);
      final viewport = 640.0 - 300; // above the keyboard
      expect(tester.getRect(find.byTooltip('Dismiss')).bottom, lessThan(viewport));
      // The header is capped at 65% of the body, so a result row stays reachable.
      final body = viewport - 56;
      expect(find.byType(TransactionTile).hitTestable(), findsWidgets);
      expect(
        tester.getRect(find.byType(TransactionTile).hitTestable().first).top,
        greaterThanOrEqualTo(56 + body * .65 - 1),
      );
      // The long answer's source chip is reachable by scrolling the header.
      await tester.ensureVisible(find.widgetWithText(ActionChip, first));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, first).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The list below is still scrollable and not starved.
      final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable));
      expect(list, findsOneWidget);
      expect(tester.getSize(find.byType(ListView)).height, greaterThan(body * .3));
    });

    testWidgets('leaving the screen while explaining: the late result throws nothing', (
      tester,
    ) async {
      await open(tester);
      runtime.hold = Completer<void>();
      await tester.runAsync(() async {
        await tester.tap(find.text('Explain results'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(services.search.explaining, isTrue);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(() async {
        runtime.hold!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(services.search.explanation, isNotNull); // controller outlives the view
    });

    testWidgets('an explain error shows the message and keeps rows and chips', (tester) async {
      await open(tester);
      runtime.nextError = StateError('native crash');
      await tapExplain(tester);
      expect(find.textContaining('Gemma could not complete'), findsOneWidget);
      expect(find.byType(ExplanationCard), findsNothing);
      expect(find.byType(TransactionTile), findsWidgets);
      expect(find.text('Explain results'), findsOneWidget);
    });
  });
}
