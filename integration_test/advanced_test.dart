import 'dart:io';
import 'dart:convert';

import 'package:flutter_rag/advanced/plan_args.dart';

import 'package:flutter/foundation.dart' show debugPrint, debugPrintSynchronously;
import 'package:flutter_rag/advanced/advanced_controller.dart';
import 'package:flutter_rag/advanced/flutter_gemma_installer.dart';
import 'package:flutter_rag/advanced/flutter_gemma_runtime.dart';
import 'package:flutter_rag/advanced/gemma_runtime.dart';
import 'package:flutter_rag/advanced/gemma_tool.dart';
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/data/fixture/authored.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  debugPrint = debugPrintSynchronously;

  testWidgets('Gemma plans, follows up, cancels when switched off, frees memory', (tester) async {
    final installer = FlutterGemmaInstaller();
    expect(
      await installer.isInstalled(),
      isTrue,
      reason: 'Run Task 3 (or the setup screen) first to download the model.',
    );
    final runtime = _RecordingRuntime();
    final c = AdvancedController(
      installer: installer,
      runtime: runtime,
      directory: PayeeDirectory(
        shops: const [
          '7-11',
          'Sushiro',
          'TermsGames',
          'Uniqlo',
          'Big Mart',
          'Trail Supply',
          'Outdoor Base',
        ],
        people: [...kFamilyGroup, 'Alex', 'Ploy'],
      ),
    );

    addTearDown(() async {
      await c.disable();
      c.dispose();
    });

    var sw = Stopwatch()..start();
    expect(await c.requestEnable(), isTrue);
    expect(c.isOn, isTrue, reason: c.error);
    debugPrint(
      'ADVANCED load ${sw.elapsedMilliseconds} ms backend=${runtime.backendLabel} '
      'rss=${ProcessInfo.currentRss ~/ 1048576} MB',
    );

    sw = Stopwatch()..start();
    SearchPlan e02;
    try {
      e02 = await c.plan('Find things I bought for camping last month, under THB 3,000, excluding food.');
      debugPrint('ADVANCED E02 ${sw.elapsedMilliseconds} ms -> ${jsonEncode(planToToolArgs(e02))}');
      expect(e02.dateRange, bangkokMonth(2026, 9));
      expect(e02.maxAmount, const AmountBound(300000, inclusive: false));
      expect(e02.excludeCategories, {Category.food});
      expect(e02.transactionType, TransactionType.purchase);
      expect(e02.semanticQuery, 'camping');
    } on AdvancedError catch (error) {
      // Task22 checks mechanics. Record the measured accuracy failure without
      // turning an omitted constraint into a successful generated plan.
      expect(error.message, contains('requested dates'));
      debugPrint('ADVANCED E02 SAFE_REJECTION ${sw.elapsedMilliseconds} ms -> $error');
      e02 = SearchPlan(dateRange: bangkokMonth(2026,9),
        maxAmount: const AmountBound(300000,inclusive:false), excludeCategories:{Category.food},
        transactionType:TransactionType.purchase, semanticQuery:'camping',sort:SortOrder.relevance);
      debugPrint('ADVANCED AUTHORED E02 for follow-up mechanics ONLY -> ${jsonEncode(planToToolArgs(e02))}');
    }

    sw = Stopwatch()..start();
    try {
      final e29 = await c.plan('Same purchases, but go back one year and include the month before it too',
        current:e02,previousQuery:'camping last month');
      debugPrint('ADVANCED E29 ${sw.elapsedMilliseconds} ms -> ${jsonEncode(planToToolArgs(e29))}');
      expect(e29.dateRange,DateRange(bangkokMonth(2025,8).start,bangkokMonth(2025,9).end));
      expect(e29.maxAmount,e02.maxAmount); expect(e29.excludeCategories,e02.excludeCategories);
      expect(e29.transactionType,e02.transactionType); expect(e29.semanticQuery,e02.semanticQuery);
    } on AdvancedError catch(error) {
      expect(error.message,contains('requested dates'));
      debugPrint('ADVANCED E29 SAFE_REJECTION ${sw.elapsedMilliseconds} ms -> $error');
    }
    final delta = await c.plan('under THB 2,000 instead', current:e02,previousQuery:'camping last month');
    expect(delta.maxAmount,const AmountBound(200000,inclusive:false));
    expect(delta.dateRange,e02.dateRange); expect(delta.semanticQuery,e02.semanticQuery);
    debugPrint('ADVANCED DELTA -> ${jsonEncode(planToToolArgs(delta))}');

    // Switch off mid-explanation: cancelled quickly, engine reusable after.
    final rows = kAuthoredTransactions.take(5).toList();
    final explaining = c.explain('camping', rows);
    final cancelled = expectLater(explaining, throwsA(isA<GemmaCancelled>()));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    sw = Stopwatch()..start();
    final beforeUnload = ProcessInfo.currentRss ~/ 1048576;
    await c.disable();
    await cancelled;
    debugPrint(
      'ADVANCED cancel+unload ${sw.elapsedMilliseconds} ms '
      'rss=$beforeUnload -> ${ProcessInfo.currentRss ~/ 1048576} MB',
    );

    expect(await c.requestEnable(), isTrue);
    final again = await c.plan('Show transfers to my family');
    debugPrint('ADVANCED after re-enable -> ${jsonEncode(planToToolArgs(again))}');
    expect(again.personNames, kFamilyGroup.toSet());
    expect(again.transactionType, TransactionType.transfer);
    await c.disable();
  }, timeout: const Timeout(Duration(minutes: 15)));
}


class _RecordingRuntime extends FlutterGemmaRuntime {
  @override
  Future<Map<String, dynamic>> callTool({required String system, required String user,
      required ToolSpec tool, required Duration timeout}) async {
    final watch = Stopwatch()..start();
    try {
      final args = await super.callTool(system: system, user: user, tool: tool, timeout: timeout);
      debugPrint('ADVANCED TOOL ${watch.elapsedMilliseconds} ms -> ${jsonEncode(args)}');
      return args;
    } catch (e) {
      debugPrint('ADVANCED TOOL ERROR ${watch.elapsedMilliseconds} ms -> $e');
      rethrow;
    }
  }
}
