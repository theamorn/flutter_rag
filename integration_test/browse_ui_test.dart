import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter_rag/app.dart';
import 'package:flutter_rag/app_services.dart';
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/results/result_pager.dart';
import 'package:flutter_rag/ui/transaction_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Started on the first line of [main], before the test body runs.
final Stopwatch sinceMain = Stopwatch();

void main() {
  sinceMain.start();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  debugPrint = debugPrintSynchronously;

  testWidgets('Task 11 browse, slip memo, and has-memo filter', (tester) async {
    final report = _Report();
    AppServices? services;
    String? originalMemo;
    var memoDirty = false;

    try {
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
      }

      final boot = Stopwatch()..start();
      services = await AppServices.boot();
      report.line(
        'boot ${boot.elapsedMilliseconds} ms fixture=${services.fixtureSize}',
      );
      final count = await services.repo.count();
      report.line(
        'repo.count $count (seedIfEmpty leaves an existing database)',
      );

      await tester.pumpWidget(TransactionSearchApp(services: services));
      final browse = services.search.browse();
      final showed = await _waitFor(
        tester,
        find.text('5500 transactions'),
        timeout: const Duration(seconds: 30),
      );
      final launchMs = sinceMain.elapsedMilliseconds;
      report.line(
        'launch_to_first_rows $launchMs ms (this process, from Dart main)',
      );
      report.line('summary_visible $showed');
      await browse;
      await tester.pump();

      final items = services.search.pager.items;
      final firstDate = items.isEmpty
          ? ''
          : formatBangkokDate(items.first.occurredAt);
      var newestFirst = items.length > 1;
      for (var i = 1; i < items.length; i++) {
        if (items[i - 1].occurredAt.isBefore(items[i].occurredAt)) {
          newestFirst = false;
          break;
        }
      }
      report.check(
        'about 100 rows, newest first, starting 30 Sep 2026',
        items.length == 100 && newestFirst && firstDate == '30 Sep 2026',
        'count=${items.length} first=$firstDate newestFirst=$newestFirst '
            'firstPayee=${items.isEmpty ? '' : items.first.payeeName}',
      );
      report.line(
        'first_rows ${items.take(5).map((t) => '${t.payeeName} ${formatBangkokDate(t.occurredAt)}').join(' | ')}',
      );
      await _shot(binding, tester, 'first-rows');
      await _dumpTexts(report, 'first-rows');

      final beforeMore = items.length;
      final spinner = _catchBottomSpinner(tester, services);
      await tester.pump(const Duration(milliseconds: 500));
      final afterMore = services.search.pager.items.length;
      report.check(
        'scrolling loads more, with a spinner at the bottom',
        spinner.saw && afterMore > beforeMore,
        'spinner=${spinner.saw} error=${spinner.error} '
            'rows $beforeMore -> $afterMore status=${services.search.pager.status}',
      );
      if (spinner.saw) await _shot(binding, tester, 'after-load-more');

      await _jumpListTo(tester, 0);
      final opened = await _openTrailSupply(tester, report);
      report.check(
        'Trail Supply on 12 Sep 2026 opens',
        opened,
        'opened=$opened',
      );
      if (opened) {
        final title = find.text('Demo transaction slip');
        await _waitFor(tester, title, timeout: const Duration(seconds: 10));
        final reference = find.text('txn_a01');
        final memoFinder = find.byKey(const Key('slip-memo'));
        originalMemo = _memoValue(tester);
        report.line('slip_memo ${originalMemo ?? '(none)'}');
        report.check(
          'slip title is Demo transaction slip and the memo is visible',
          title.evaluate().isNotEmpty &&
              reference.evaluate().isNotEmpty &&
              memoFinder.evaluate().isNotEmpty &&
              (originalMemo?.isNotEmpty ?? false),
          'title=${title.evaluate().length} reference=${reference.evaluate().length} '
              'memoKey=${memoFinder.evaluate().length} memo=${originalMemo ?? '(none)'}',
        );
        await _shot(binding, tester, 'slip');
        await _dumpTexts(report, 'slip');

        const edited = 'Task 11 temporary memo';
        await _setMemo(tester, edited);
        memoDirty = true;
        final editedShown = await _waitFor(
          tester,
          find.text(edited),
          timeout: const Duration(seconds: 90),
        );
        report.check(
          'editing the memo works',
          editedShown,
          'saw "$edited": $editedShown',
        );
        await _shot(binding, tester, 'memo-edited');

        await _tapText(tester, 'Edit memo');
        await _tapText(tester, 'Clear');
        final hidden = await _waitUntil(
          tester,
          () =>
              find.byKey(const Key('slip-memo')).evaluate().isEmpty &&
              find.text('Add memo').evaluate().isNotEmpty,
          timeout: const Duration(seconds: 90),
        );
        report.check(
          'Clear hides the memo field',
          hidden,
          'slip-memo gone and Add memo shown: $hidden',
        );
        await _shot(binding, tester, 'memo-cleared');

        await _setMemo(tester, originalMemo!);
        final restoredOnSlip = await _waitFor(
          tester,
          find.text(originalMemo),
          timeout: const Duration(seconds: 90),
        );
        final stored = await services.repo.getById('txn_a01');
        memoDirty = stored?.memo != originalMemo;
        report.check(
          'original memo restored',
          restoredOnSlip && stored?.memo == originalMemo,
          'onSlip=$restoredOnSlip stored=${stored?.memo}',
        );
        await tester.tap(find.text('Close'));
        await tester.pump(const Duration(milliseconds: 400));
      }

      await _tapText(tester, 'Add filter');
      final hasMemo = await _waitFor(
        tester,
        find.text('Has memo'),
        timeout: const Duration(seconds: 10),
      );
      if (hasMemo) {
        await tester.tap(find.text('Has memo').last);
        await tester.pump();
      }
      final saw550 = await _waitFor(
        tester,
        find.text('550 transactions'),
        timeout: const Duration(seconds: 20),
      );
      report.check(
        'Has memo shows 550 transactions',
        hasMemo && saw550,
        'sheet=$hasMemo label=${saw550 ? '550 transactions' : _countLabel()}',
      );
      await _shot(binding, tester, 'has-memo');
      await _dumpTexts(report, 'has-memo');

      final chip = find.byTooltip('Remove Has memo');
      final hadChip = chip.evaluate().isNotEmpty;
      if (hadChip) {
        await tester.tap(chip);
        await tester.pump();
      }
      final saw5500 = await _waitFor(
        tester,
        find.text('5500 transactions'),
        timeout: const Duration(seconds: 20),
      );
      report.check(
        'removing the chip returns 5500 transactions',
        hadChip && saw5500,
        'chipTapped=$hadChip label=${saw5500 ? '5500 transactions' : _countLabel()}',
      );
      await _shot(binding, tester, 'full-set');
      await _dumpTexts(report, 'full-set');
    } finally {
      if (memoDirty && services != null && originalMemo != null) {
        try {
          await services.search.updateMemo('txn_a01', originalMemo);
          final stored = await services.repo.getById('txn_a01');
          report.line('finally restored memo=${stored?.memo}');
          memoDirty = stored?.memo != originalMemo;
        } catch (e) {
          report.line('finally restore failed: $e');
        }
      }
      report.line(
        report.failed == 0 ? 'OVERALL PASS' : 'OVERALL FAIL ${report.failed}',
      );
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/task11_browse_check.txt');
        await file.writeAsString(report.text);
        debugPrint('BROWSE_REPORT_PATH ${file.path}');
      } catch (e) {
        debugPrint('BROWSE_REPORT_WRITE_FAILED $e');
      }
      debugPrint('BROWSE_REPORT_BEGIN\n${report.text}\nBROWSE_REPORT_END');
      await services?.dispose();
    }

    expect(report.failed, 0, reason: report.text);
  }, timeout: const Timeout(Duration(minutes: 8)));
}

class _Report {
  final _lines = <String>[];
  int failed = 0;

  void line(String text) {
    _lines.add(text);
    debugPrint('BROWSE $text');
  }

  void check(String name, bool ok, String observed) {
    if (!ok) failed++;
    line('${ok ? 'PASS' : 'FAIL'} | $name | $observed');
  }

  String get text => _lines.join('\n');
}

class _Spinner {
  bool saw = false;
  String error = '';
}

_Spinner _catchBottomSpinner(WidgetTester tester, AppServices services) {
  final result = _Spinner();
  final before = services.search.pager.items.length;

  var loadingMore = false;
  void onPager() {
    if (services.search.pager.status == PagerStatus.loadingMore) {
      loadingMore = true;
    }
  }

  services.search.pager.addListener(onPager);
  try {
    final scrollable = find.descendant(
      of: find.byType(TransactionList),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    if (position.maxScrollExtent <= 0) {
      result.error = 'maxScrollExtent ${position.maxScrollExtent}';
      return result;
    }
    position.jumpTo(position.maxScrollExtent);
    // The page fetch is still pending. Lay out now, after jumpTo has
    // unlocked the position, while the footer is still loadingMore.
    final binding = tester.binding;
    final root = binding.rootElement;
    if (root != null) {
      binding.buildOwner!.buildScope(root);
      binding.buildOwner!.finalizeTree();
      binding.pipelineOwner.flushLayout();
      binding.pipelineOwner.flushCompositingBits();
      binding.pipelineOwner.flushPaint();
    }
    result.saw =
        loadingMore &&
        find
            .descendant(
              of: find.byType(TransactionList),
              matching: find.byType(CircularProgressIndicator),
            )
            .evaluate()
            .isNotEmpty;
    if (!result.saw) {
      result.error =
          'loadingMore=$loadingMore status=${services.search.pager.status} '
          'indicators=${find.byType(CircularProgressIndicator).evaluate().length}';
    }
    if (!loadingMore && services.search.pager.items.length == before) {
      result.error =
          'loadMore did not start (status=${services.search.pager.status})';
    }
  } catch (e) {
    result.error = e.toString();
  } finally {
    services.search.pager.removeListener(onPager);
  }
  return result;
}

Future<void> _jumpListTo(WidgetTester tester, double offset) async {
  final list = find.descendant(
    of: find.byType(TransactionList),
    matching: find.byType(Scrollable),
  );
  if (list.evaluate().isEmpty) return;
  tester.state<ScrollableState>(list).position.jumpTo(offset);
  await tester.pump();
}

Future<bool> _openTrailSupply(WidgetTester tester, _Report report) async {
  final target = _trailTile();
  for (var hop = 0; hop < 40; hop++) {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target.first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(target.first);
      await tester.pump(const Duration(milliseconds: 400));
      report.line('trail_supply_hop $hop');
      return true;
    }
    final list = find.descendant(
      of: find.byType(TransactionList),
      matching: find.byType(Scrollable),
    );
    if (list.evaluate().isEmpty) return false;
    await tester.drag(list, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 200));
  }
  return false;
}

Finder _trailTile() => find.byElementPredicate((el) {
  if (el.widget is! ListTile) return false;
  final texts = _textsOf(el);
  return texts.contains('Trail Supply') &&
      texts.any((t) => t.contains('12 Sep 2026'));
});

String? _memoValue(WidgetTester tester) {
  final fields = find.byKey(const Key('slip-memo')).evaluate();
  if (fields.isEmpty) return null;
  final texts = _textsOf(fields.first).where((t) => t != 'Memo').toList();
  return texts.isEmpty ? null : texts.join('\n');
}

Future<void> _setMemo(WidgetTester tester, String value) async {
  final edit = find.text('Edit memo');
  final add = find.text('Add memo');
  if (edit.evaluate().isNotEmpty) {
    await tester.tap(edit);
  } else {
    await tester.tap(add);
  }
  await _waitFor(
    tester,
    find.text('Save'),
    timeout: const Duration(seconds: 10),
  );
  final field = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(EditableText),
  );
  // The device IME is not the widget-test text input, so enterText never
  // reaches this field. Set the dialog's own controller, which Save reads.
  tester.state<EditableTextState>(field).widget.controller.value =
      TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
  await tester.pump();
  await tester.tap(
    find.descendant(of: find.byType(AlertDialog), matching: find.text('Save')),
  );
  await tester.pump();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await _waitFor(tester, finder, timeout: const Duration(seconds: 10));
  await tester.ensureVisible(finder.last);
  await tester.tap(finder.last);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<bool> _waitFor(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
}) {
  return _waitUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    timeout: timeout,
  );
}

Future<bool> _waitUntil(
  WidgetTester tester,
  bool Function() ready, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (ready()) return true;
    await tester.pump(const Duration(milliseconds: 100));
  }
  return ready();
}

String _countLabel() {
  final labels = <String>[];
  for (final el in find.byType(Text).evaluate()) {
    final data = (el.widget as Text).data;
    if (data != null && data.contains('transaction')) labels.add(data);
  }
  return labels.isEmpty ? '(no count label)' : labels.join(', ');
}

List<String> _textsOf(Element root) {
  final texts = <String>[];
  void walk(Element e) {
    final widget = e.widget;
    if (widget is Text && widget.data != null && widget.data!.isNotEmpty) {
      texts.add(widget.data!);
    }
    e.visitChildren(walk);
  }

  walk(root);
  return texts;
}

Future<void> _dumpTexts(_Report report, String name) async {
  final texts = <String>[];
  for (final el in find.byType(Text).evaluate()) {
    final data = (el.widget as Text).data;
    if (data != null && data.isNotEmpty) texts.add(data);
  }
  report.line('TEXTS $name ${texts.join(' || ')}');
}

Future<void> _shot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  try {
    await tester.pump();
    final bytes = await binding.takeScreenshot(name);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/task11_$name.png');
    await file.writeAsBytes(bytes);
    debugPrint('BROWSE screenshot $name ${file.path} ${bytes.length} bytes');
  } catch (e) {
    debugPrint('BROWSE screenshot $name failed: $e');
  }
}
