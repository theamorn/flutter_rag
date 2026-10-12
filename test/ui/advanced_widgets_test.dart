import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rag/advanced/advanced_controller.dart';
import 'package:flutter_rag/app_services.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/ui/advanced_switch.dart';
import 'package:flutter_rag/ui/gemma_setup_card.dart';
import 'package:flutter_rag/ui/search_screen.dart';
import 'package:flutter_rag/ui/setup_screen.dart';
import '../support/fake_rag_index.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gemma.dart';

void main() {
  late FakeGemmaInstaller installer;
  late FakeGemmaRuntime runtime;
  late AdvancedController controller;
  void configure() {
    installer = FakeGemmaInstaller();
    runtime = FakeGemmaRuntime();
    controller = AdvancedController(
      installer: installer,
      runtime: runtime,
      directory: PayeeDirectory(shops: [], people: []),
    );
  }

  tearDown(() async {
    controller.dispose();
  });
  testWidgets('off is lazy; missing model requests setup; load error stays off', (tester) async {
    configure();
    var setup = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdvancedSwitch(controller: controller, onNeedsSetup: () => setup++),
        ),
      ),
    );
    expect(runtime.loadCalls, 0);
    expect(controller.install, ModelInstallState.unknown);
    await tester.tap(find.text('Advanced reasoning'));
    await tester.pumpAndSettle();
    expect(setup, 1);
    installer.installed = true;
    runtime.loadError = StateError('GPU');
    await tester.tap(find.text('Advanced reasoning'));
    await tester.pumpAndSettle();
    expect(setup, 1);
    expect(controller.isOn, isFalse);
    expect(find.textContaining('Could not load Gemma'), findsOneWidget);
  });
  testWidgets('the switch keeps its exact title and subtitle', (tester) async {
    configure();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdvancedSwitch(controller: controller, onNeedsSetup: () {})),
      ),
    );
    expect(find.text('Advanced reasoning'), findsOneWidget);
    expect(
      find.text('Use the optional on-device model for complex questions and explanations.'),
      findsOneWidget,
    );
  });
  testWidgets('setup checks without loading; enabling blocks repeat buttons', (tester) async {
    configure();
    installer.installed = true;
    runtime.loadHold = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GemmaSetupCard(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(runtime.loadCalls, 0);
    await tester.tap(find.text('Enable'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Loading Gemma 4 E2B…'), findsOneWidget);
    expect(find.text('Enable'), findsNothing);
    runtime.loadHold!.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off and free memory'));
    await tester.pumpAndSettle();
    expect(controller.isOn, isFalse);
    expect(installer.installed, isTrue);
  });
  testWidgets('download progress, cancel, retry and load failure are visible', (tester) async {
    configure();
    installer.hold = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GemmaSetupCard(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Download and enable'));
    await tester.pump();
    await tester.pump();
    expect(find.text('10%'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    installer.hold!.complete();
    await tester.pumpAndSettle();
    expect(controller.isOn, isFalse);
    expect(find.text('Download cancelled.'), findsOneWidget);
    installer.hold = null;
    installer.failWith = StateError('network');
    await tester.tap(find.textContaining('Download and enable'));
    await tester.pumpAndSettle();
    expect(find.text('Retry download'), findsOneWidget);
    installer.failWith = null;
    await tester.tap(find.text('Retry download'));
    await tester.pumpAndSettle();
    expect(controller.isOn, isTrue);
  });
  testWidgets('compact screen with keyboard scrolls controls and keeps lazy results', (
    tester,
  ) async {
    configure();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    final services = (await tester.runAsync(
      () => AppServices.open(AppDatabase.memory(), 300, installer: installer, runtime: runtime),
    ))!;
    addTearDown(() => tester.runAsync(services.dispose));
    await tester.runAsync(() => services.search.submit('Show my 7-11 payments last month'));
    await tester.pumpWidget(MaterialApp(home: SearchScreen(services: services)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('refine')), findsOneWidget);
  });
  testWidgets('setup has one optional Gemma card alongside the index card', (tester) async {
    configure();
    final services = (await tester.runAsync(() => AppServices.open(AppDatabase.memory(), 300,
      installer: installer, runtime: runtime, rag: FakeRagIndex())))!;
    addTearDown(() => tester.runAsync(services.dispose));
    await tester.pumpWidget(MaterialApp(home: SetupScreen(services: services)));
    await tester.pumpAndSettle();
    expect(find.byType(GemmaSetupCard), findsOneWidget);
    expect(runtime.loadCalls, 0);
  });

}
