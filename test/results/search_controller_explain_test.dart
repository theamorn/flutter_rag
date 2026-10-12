import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/advanced/advanced_controller.dart';
import 'package:flutter_rag/advanced/explainer.dart';
import 'package:flutter_rag/advanced/gemma_runtime.dart';
import 'package:flutter_rag/app_services.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/results/search_controller.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gemma.dart';

/// An advanced controller whose explain() throws something other than the
/// documented errors, to prove `explaining` can never stick on.
class _ThrowingAdvanced extends AdvancedController {
  _ThrowingAdvanced({required super.installer, required super.runtime, required super.directory});

  @override
  Future<Explanation> explain(
    String query,
    List<Transaction> rows, {
    SearchPlan? plan,
  }) async =>
      throw StateError('boom');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // The plan's sample used Mom, but the 300-row fixture has only 2 Mom rows;
  // Kids has 6, so a sixth row exists that must NOT reach the model.
  test('explain uses the first 5 shown rows; a new search clears it', () async {
    final runtime = FakeGemmaRuntime();
    final services = await AppServices.open(
      AppDatabase.memory(),
      300,
      installer: FakeGemmaInstaller()..installed = true,
      runtime: runtime,
    );
    await services.search.applyPlan(const SearchPlan(personNames: {'Kids'}));
    await services.search.explain(); // off: nothing happens
    expect(services.search.explanation, isNull);
    expect(runtime.generateCalls, 0);

    await services.advanced!.requestEnable();
    final first = services.search.pager.items.first.id;
    runtime.nextText = 'Your support for the kids [$first].';
    await services.search.explain();
    expect(services.search.explanation!.citedIds, [first]);
    expect(runtime.lastUser!.split('\n').where((l) => l.startsWith('[txn_')).length, 5);

    await services.search.applyPlan(const SearchPlan(personNames: {'Dad'}));
    expect(services.search.explanation, isNull);
    await services.dispose();
  });

  group('races', () {
    late AppServices services;
    late FakeGemmaRuntime runtime;
    late String first;
    late Future<void> explainFuture;

    late TransactionSearchController search;

    setUp(() async {
      runtime = FakeGemmaRuntime();
      services = await AppServices.open(
        AppDatabase.memory(),
        300,
        installer: FakeGemmaInstaller()..installed = true,
        runtime: runtime,
      );
      search = services.search;
      await search.applyPlan(const SearchPlan(personNames: {'Kids'}));
      await services.advanced!.requestEnable();
      first = search.pager.items.first.id;
      runtime.nextText = 'Support for Kids [$first].';
    });
    tearDown(() => services.dispose());

    /// Starts an explanation and parks it inside the native call.
    Future<void> startHeldExplain() async {
      runtime.hold = Completer<void>();
      final pending = search.explain();
      await Future<void>.delayed(Duration.zero);
      expect(search.explaining, isTrue);
      expect(runtime.generateCalls, 1);
      explainFuture = pending;
    }

    for (final replacement in ['browse', 'chips', 'submit', 'refine']) {
      test('$replacement invalidates an in-flight explanation at its start', () async {
        await startHeldExplain();
        Future<void> next;
        switch (replacement) {
          case 'browse':
            next = search.browse();
          case 'chips':
            next = search.applyPlan(const SearchPlan(personNames: {'Dad'}));
          case 'submit':
            runtime.nextArgs = {
              'shops': ['7-11'],
            };
            next = search.submit('my 7-11 runs');
          default:
            runtime.nextArgs = {
              'shops': ['7-11'],
            };
            next = search.refine('only 7-11');
        }
        // Immediately, before any new result lands.
        expect(search.explanation, isNull, reason: replacement);
        expect(search.explaining, isFalse, reason: replacement);
        runtime.hold!.complete();
        await explainFuture;
        await next;
        expect(search.explanation, isNull, reason: 'late result must not land');
        expect(search.explaining, isFalse);
        expect(search.busy, isFalse);
      });
    }

    test('a finished explanation is cleared as soon as a new search starts', () async {
      await search.explain();
      expect(search.explanation, isNotNull);
      runtime.nextArgs = {
        'shops': ['7-11'],
      };
      final next = search.submit('my 7-11 runs');
      expect(search.explanation, isNull);
      await next;
      expect(search.explanation, isNull);
    });

    test(
      'toggle off clears explaining and explanation at once; re-enable cannot revive it',
      () async {
        runtime.ignoreCancel = true; // native work finishes only when it wants to
        await startHeldExplain();
        final stopped = services.advanced!.disable();
        expect(search.explaining, isFalse);
        expect(search.explanation, isNull);
        final enabling = services.advanced!.requestEnable();
        runtime.hold!.complete();
        await explainFuture;
        await stopped;
        await enabling;
        expect(services.advanced!.isOn, isTrue);
        expect(search.explanation, isNull);
        expect(search.explaining, isFalse);
      },
    );

    test('toggle off with a finished explanation clears it', () async {
      await search.explain();
      expect(search.explanation, isNotNull);
      await services.advanced!.disable();
      expect(search.explanation, isNull);
      expect(search.errors, isEmpty);
    });

    test(
      'dismiss during an in-flight explain: it never reappears, native work is cancelled',
      () async {
        await startHeldExplain();
        search.dismissExplanation();
        expect(search.explaining, isFalse);
        expect(search.explanation, isNull);
        runtime.hold!.complete();
        await explainFuture;
        expect(search.explanation, isNull);
        expect(runtime.cancelCalls, greaterThan(0));
        // Explaining again still works afterwards.
        runtime.hold = null;
        await search.explain();
        expect(search.explanation!.citedIds, [first]);
      },
    );

    test('repeated presses while one is running queue no extra native job', () async {
      await startHeldExplain();
      final again = [search.explain(), search.explain(), search.explain()];
      runtime.hold!.complete();
      await explainFuture;
      await Future.wait(again);
      expect(runtime.generateCalls, 1);
      expect(services.advanced!.jobsStarted, 1);
      expect(search.explanation!.citedIds, [first]);
    });

    test('after a chip edit the old query text is not sent with the new rows', () async {
      await services.advanced!.disable();
      await search.submit('Show transfers to Mom');
      await services.advanced!.requestEnable();
      expect(search.lastQuery, 'Show transfers to Mom');
      await search.explain();
      expect(runtime.lastUser, contains('Search: Show transfers to Mom'));
      await search.applyPlan(const SearchPlan(personNames: {'Dad'}));
      runtime.nextText = 'Dad [${search.pager.items.first.id}].';
      await search.explain();
      expect(runtime.lastUser, isNot(contains('Mom')));
      expect(runtime.lastUser, contains(search.pager.items.first.id));
    });

    test('a memo rerun keeps a current query but not a stale one', () async {
      await services.advanced!.disable();
      await search.submit('Show transfers to Mom');
      await services.advanced!.requestEnable();
      await search.updateMemo(search.pager.items.first.id, 'Rent share');
      runtime.nextText = 'Mom [${search.pager.items.first.id}].';
      await search.explain();
      expect(runtime.lastUser, contains('Search: Show transfers to Mom'));
      await search.applyPlan(const SearchPlan(personNames: {'Dad'}));
      await search.updateMemo(search.pager.items.first.id, 'Bill');
      runtime.nextText = 'Dad [${search.pager.items.first.id}].';
      await search.explain();
      expect(runtime.lastUser, isNot(contains('Mom')));
    });

    test('a grouped citation is accepted, not reported as removed', () async {
      final second = search.pager.items[1].id;
      runtime.nextText = 'Both [$first, $second].';
      await search.explain();
      expect(search.explanation!.citedIds, [first, second]);
      expect(search.explanation!.invalidIds, isEmpty);
      expect(search.explanation!.isUsable, isTrue);
    });

    test('updateMemo invalidates an in-flight explanation at its start', () async {
      await startHeldExplain();
      final save = search.updateMemo(first, 'A new memo');
      expect(search.explaining, isFalse);
      expect(search.explanation, isNull);
      runtime.hold!.complete();
      await explainFuture;
      await save;
      expect(search.explanation, isNull, reason: 'built from the old memo');
    });

    test('a chip edit cancels a stale advanced plan so Explain starts at once', () async {
      runtime.hold = Completer<void>();
      runtime.nextArgs = {'shops': ['7-11']};
      final plan = search.submit('my 7-11 runs');
      await Future<void>.delayed(Duration.zero);
      expect(runtime.toolCalls, 1);
      await search.applyPlan(const SearchPlan(personNames: {'Kids'}));
      runtime.hold = null; // new jobs run freely; only the stale plan is parked
      final explain = search.explain();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runtime.generateCalls, 1, reason: 'not queued behind the outdated plan');
      await explain;
      await plan;
      expect(search.explanation, isNotNull);
    });

    test('advanced refine after a chip edit sends no stale previous question', () async {
      await services.advanced!.disable();
      await search.submit('purchases excluding food');
      await services.advanced!.requestEnable();
      expect(search.plan.excludeCategories, isNotEmpty);
      await search.applyPlan(search.plan.copyWith(excludeCategories: {}));
      runtime.nextArgs = {'date_from': '2025-01-01', 'date_to': '2025-12-31'};
      await search.refine('last year');
      expect(runtime.lastUser, isNot(contains('purchases excluding food')));
      expect(runtime.lastUser, contains('Follow-up: last year'));
      // Without a chip edit the previous question is still sent.
      runtime.nextArgs = {'date_from': '2024-01-01', 'date_to': '2024-12-31'};
      await search.refine('the year before');
      expect(runtime.lastUser, contains('Previous question: last year'));
    });

    test('an explain error shows the message and keeps query, chips and rows', () async {
      await search.submit('Show transfers to Mom last year');
      final plan = search.plan;
      final query = search.lastQuery;
      final ids = search.pager.items.map((t) => t.id).toList();
      runtime.nextError = StateError('native crash');
      await search.explain();
      expect(search.errors.single, contains('Gemma could not complete'));
      expect(search.explaining, isFalse);
      expect(search.explanation, isNull);
      expect(search.plan, plan);
      expect(search.lastQuery, query);
      expect(search.pager.items.map((t) => t.id), ids);
      expect(search.busy, isFalse);
      // The next search clears the error as usual.
      await search.applyPlan(plan);
      expect(search.errors, isEmpty);
    });

    test('a timeout settles explaining and keeps the rows', () async {
      final ids = search.pager.items.map((t) => t.id).toList();
      runtime.nextError = const GemmaTimeout(Duration(seconds: 30));
      await search.explain();
      expect(search.explaining, isFalse);
      expect(search.errors, isNotEmpty);
      expect(search.pager.items.map((t) => t.id), ids);
    });

    test('an unexpected exception still settles explaining', () async {
      final throwing = _ThrowingAdvanced(
        installer: FakeGemmaInstaller()..installed = true,
        runtime: runtime,
        directory: services.directory,
      );
      addTearDown(throwing.dispose);
      await throwing.requestEnable();
      final controller = TransactionSearchController(
        repo: services.repo,
        engine: search.engine,
        validator: search.validator,
        interpreter: search.interpreter,
        refiner: search.refiner,
        advanced: throwing,
      );
      addTearDown(controller.dispose);
      await controller.applyPlan(const SearchPlan(personNames: {'Kids'}));
      await controller.explain();
      expect(controller.explaining, isFalse);
      expect(controller.errors.single, contains('boom'));
      expect(controller.pager.items, isNotEmpty);
      expect(controller.plan.personNames, {'Kids'});
    });

    test('the model sees only 5 rows with original memos; no memo gets no invented text', () async {
      await search.updateMemo(first, null);
      await search.explain();
      final lines = runtime.lastUser!.split('\n').where((l) => l.startsWith('[txn_')).toList();
      final rows = search.pager.items.take(5).toList();
      expect(lines.length, 5);
      for (var i = 0; i < 5; i++) {
        final t = rows[i];
        expect(lines[i], startsWith('[${t.id}]'));
        expect(lines[i], endsWith('memo: ${t.memo == null ? '(none)' : jsonEncode(t.memo)}'));
      }
      expect(lines.first, endsWith('memo: (none)'));
      expect(runtime.lastUser, isNot(contains('purpose')));
      // A sixth row is not sent.
      final sixth = search.pager.items[5].id;
      expect(runtime.lastUser, isNot(contains('[$sixth]')));
    });

    test('invented citations are removed and a citation of an unsent row is invalid', () async {
      final sixth = search.pager.items[5].id;
      runtime.nextText = 'Kids [$first] and [txn_9999] and [$sixth].';
      await search.explain();
      final e = search.explanation!;
      expect(e.citedIds, [first]);
      expect(e.invalidIds, ['txn_9999', sixth]);
      expect(e.text, isNot(contains('txn_9999')));
    });

    test('an uncited answer is stored unusable', () async {
      runtime.nextText = 'You went camping.';
      await search.explain();
      expect(search.explanation!.isUsable, isFalse);
    });

    test('rows stay while explaining and busy is not set by explain', () async {
      final ids = search.pager.items.map((t) => t.id).toList();
      await startHeldExplain();
      expect(search.pager.items.map((t) => t.id), ids);
      expect(search.plan.personNames, {'Kids'});
      runtime.hold!.complete();
      await explainFuture;
      expect(search.explanation, isNotNull);
    });

    test('dispose while explaining: the late result does not notify', () async {
      final controller = TransactionSearchController(
        repo: services.repo,
        engine: search.engine,
        validator: search.validator,
        interpreter: search.interpreter,
        refiner: search.refiner,
        advanced: services.advanced,
      );
      await controller.applyPlan(const SearchPlan(personNames: {'Kids'}));
      var notified = 0;
      controller.addListener(() => notified++);
      runtime.hold = Completer<void>();
      final pending = controller.explain();
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      final before = notified;
      runtime.hold!.complete();
      await pending; // would throw "used after dispose" if it notified
      expect(notified, before);
    });

    test('explain forwards the active plan so amount filter note and subtotal reach the prompt', () async {
      await search.applyPlan(
        const SearchPlan(
          personNames: {'Kids'},
          maxAmount: AmountBound(500000, inclusive: true),
        ),
      );
      final shown = search.pager.items.take(kMaxExplainRows).toList();
      expect(shown, isNotEmpty);
      runtime.nextText = 'Kids [${shown.first.id}].';
      await search.explain();
      expect(
        runtime.lastUser,
        contains(
          'Amount filter (<= THB 5,000.00) applies to each individual transaction, not the combined subtotal.',
        ),
      );
      expect(
        runtime.lastUser,
        contains('Subtotal of shown transactions (${shown.length}):'),
      );
    });
  });
}
