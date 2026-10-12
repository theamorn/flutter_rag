import 'dart:async';

import 'package:flutter_rag/advanced/advanced_controller.dart';
import 'package:flutter_rag/advanced/gemma_runtime.dart';
import 'package:flutter_rag/advanced/gemma_installer.dart';
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/data/fixture/authored.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gemma.dart';

final dir = PayeeDirectory(
  shops: const ['7-11', 'Trail Supply'],
  people: kFamilyGroup,
);
const e02Args = {
  'date_from': '2026-09-01',
  'date_to': '2026-09-30',
  'amount_max': 3000,
  'exclude_categories': ['food'],
  'transaction_type': 'purchase',
  'semantic_query': 'camping',
};
final e02 = SearchPlan(
  dateRange: bangkokMonth(2026, 9),
  maxAmount: const AmountBound(300000, inclusive: false),
  excludeCategories: const {Category.food},
  transactionType: TransactionType.purchase,
  semanticQuery: 'camping',
  sort: SortOrder.relevance,
);

void main() {
  late FakeGemmaInstaller installer;
  late FakeGemmaRuntime runtime;
  late AdvancedController c;

  tearDown(() => c.dispose());

  setUp(() {
    installer = FakeGemmaInstaller();
    runtime = FakeGemmaRuntime();
    c = AdvancedController(
      installer: installer,
      runtime: runtime,
      directory: dir,
    );
  });

  Future<void> turnOn() async {
    installer.installed = true;
    expect(await c.requestEnable(), isTrue);
    expect(c.isOn, isTrue);
  }

  test('default off; switching on without the model asks for setup and loads nothing', () async {
    expect(c.toggle, AdvancedToggle.off);
    expect(await c.requestEnable(), isFalse);
    expect(c.toggle, AdvancedToggle.off);
    expect(c.install, ModelInstallState.notInstalled);
    expect(runtime.loadCalls, 0);
  });

  test('download and enable: progress, verified install, load, on', () async {
    final progress = <int>[];
    c.addListener(() => progress.add(c.downloadProgress));
    await c.downloadAndEnable();
    expect(progress, containsAllInOrder([10, 50, 100]));
    expect(c.install, ModelInstallState.installed);
    expect(installer.activateCalls, 1);
    expect(runtime.loadCalls, 1);
    expect(c.isOn, isTrue);
  });

  test('cancelled download leaves the switch off and offers retry', () async {
    installer.hold = Completer<void>();
    final download = c.downloadAndEnable();
    await Future<void>.delayed(Duration.zero);
    c.cancelDownload();
    installer.hold!.complete();
    await download;
    expect(c.install, ModelInstallState.notInstalled);
    expect(c.error, 'Download cancelled.');
    expect(c.toggle, AdvancedToggle.off);
  });

  test(
    'failed download or load leaves the switch off with a message',
    () async {
      installer.failWith = StateError('disk full');
      await c.downloadAndEnable();
      expect(c.install, ModelInstallState.failed);
      expect(c.toggle, AdvancedToggle.off);

      installer
        ..failWith = null
        ..installed = true;
      runtime.loadError = StateError('GPU busy');
      expect(await c.requestEnable(), isTrue);
      expect(c.toggle, AdvancedToggle.off);
      expect(c.error, contains('GPU busy'));
    },
  );

  test('no Gemma job while off', () async {
    await expectLater(c.plan('anything'), throwsA(isA<AdvancedError>()));
    expect(runtime.toolCalls, 0);
    expect(c.jobsStarted, 0);
  });

  test(
    'plans from tool arguments; the prompt carries the date rules',
    () async {
      await turnOn();
      runtime.nextArgs = e02Args;
      expect(
        await c.plan(
          'Find things I bought for camping last month, under THB 3,000, excluding food.',
        ),
        e02,
      );
      expect(runtime.lastSystem, contains('2026-09-01 to 2026-09-30'));
      expect(c.jobsStarted, 1);
    },
  );

  test('follow-ups send the current filters and merge a delta (E29)', () async {
    await turnOn();
    runtime.nextArgs = {'date_from': '2025-08-01', 'date_to': '2025-09-30'};
    final plan = await c.plan(
      'Same purchases, but go back one year and include the month before it too',
      current: e02,
      previousQuery: 'camping last month',
    );
    expect(
      plan,
      e02.copyWith(
        dateRange: DateRange(bangkokToUtc(2025, 8), bangkokToUtc(2025, 10)),
      ),
    );
    expect(runtime.lastUser, contains('Current filters'));
  });

  test('bad arguments and prose become readable errors', () async {
    await turnOn();
    runtime.nextArgs = {
      'exclude_categories': ['gadgets'],
    };
    await expectLater(
      c.plan('x'),
      throwsA(
        isA<AdvancedError>().having(
          (e) => e.message,
          'message',
          contains('Unknown category'),
        ),
      ),
    );
    runtime.nextError = GemmaNoToolCall('Here are your payments...');
    await expectLater(
      c.plan('x'),
      throwsA(
        isA<AdvancedError>().having(
          (e) => e.message,
          'message',
          contains('without filters'),
        ),
      ),
    );
  });

  test(
    'Review Focus 5: switching off mid-generation cancels and discards',
    () async {
      await turnOn();
      runtime
        ..nextArgs = e02Args
        ..hold = Completer<void>();
      final pending = c.plan('camping');
      final cancelled = expectLater(pending, throwsA(isA<GemmaCancelled>()));
      await Future<void>.delayed(Duration.zero);
      await c.disable();
      await cancelled;
      expect(c.toggle, AdvancedToggle.off);
      expect(runtime.unloadCalls, 1);
      runtime.hold!.complete();
      await expectLater(c.plan('again'), throwsA(isA<AdvancedError>()));
    },
  );

  test('planning cancels an in-flight explanation first', () async {
    await turnOn();
    runtime
      ..hold = Completer<void>()
      ..nextArgs = e02Args;
    final explaining = c.explain(
      'camping',
      kAuthoredTransactions.take(3).toList(),
    );
    final cancelled = expectLater(explaining, throwsA(isA<GemmaCancelled>()));
    await Future<void>.delayed(Duration.zero);
    final planning = c.plan('camping');
    await cancelled;
    runtime.hold!.complete();
    expect(await planning, e02);
  });

  test(
    'switching off while the model loads keeps it off and unloads',
    () async {
      installer.installed = true;
      runtime.loadHold = Completer<void>();
      final enabling = c.requestEnable();
      await Future<void>.delayed(Duration.zero);
      expect(c.toggle, AdvancedToggle.enabling);
      final disabling = c.disable();
      expect(c.toggle, AdvancedToggle.off);
      await expectLater(c.plan('while loading'), throwsA(isA<AdvancedError>()));
      runtime.loadHold!.complete();
      await disabling;
      await enabling;
      expect(c.toggle, AdvancedToggle.off);
      expect(runtime.isLoaded, isFalse);
      expect(runtime.unloadCalls, greaterThanOrEqualTo(1));
    },
  );

  test('explanations are validated against the shown rows (max 5)', () async {
    await turnOn();
    runtime.nextText =
        'Camping gear [txn_a01] and a tent [txn_a02], plus [txn_9999].';
    final rows = kAuthoredTransactions.take(8).toList();
    final e = await c.explain('camping', rows);
    expect(e.citedIds, ['txn_a01', 'txn_a02']);
    expect(e.invalidIds, ['txn_9999']);
    expect(
      runtime.lastUser!.split('\n').where((l) => l.startsWith('[txn_')).length,
      5,
    );
  });
  test(
    'queued explanations are cancelled before any late native call',
    () async {
      await turnOn();
      runtime
        ..ignoreCancel = true
        ..hold = Completer<void>();
      final first = c.explain('one', kAuthoredTransactions.take(1).toList());
      final firstCancelled = expectLater(first, throwsA(isA<GemmaCancelled>()));
      await Future<void>.delayed(Duration.zero);
      final second = c.explain('two', kAuthoredTransactions.take(1).toList());
      final secondCancelled = expectLater(
        second,
        throwsA(isA<GemmaCancelled>()),
      );
      final disabling = c.disable();
      await firstCancelled;
      await secondCancelled;
      expect(c.toggle, AdvancedToggle.off);
      runtime.hold!.complete();
      await disabling;
      expect(runtime.generateCalls, 1);
      expect(c.jobsStarted, 1);
    },
  );

  test(
    'planning discards a late explanation and skips queued explanations',
    () async {
      await turnOn();
      runtime
        ..ignoreCancel = true
        ..hold = Completer<void>()
        ..nextArgs = e02Args;
      final first = c.explain('one', kAuthoredTransactions.take(1).toList());
      final firstCancelled = expectLater(first, throwsA(isA<GemmaCancelled>()));
      await Future<void>.delayed(Duration.zero);
      final second = c.explain('two', kAuthoredTransactions.take(1).toList());
      final secondCancelled = expectLater(
        second,
        throwsA(isA<GemmaCancelled>()),
      );
      final planning = c.plan('camping');
      await firstCancelled;
      await secondCancelled;
      expect(runtime.toolCalls, 0);
      runtime.hold!.complete();
      expect(await planning, e02);
      expect(runtime.generateCalls, 1);
      expect(runtime.maxConcurrentJobs, 1);
    },
  );

  test('newer plans discard late and queued previous plans', () async {
    await turnOn();
    runtime
      ..ignoreCancel = true
      ..hold = Completer<void>()
      ..nextArgs = e02Args;
    final first = c.plan('one');
    final firstCancelled = expectLater(first, throwsA(isA<GemmaCancelled>()));
    await Future<void>.delayed(Duration.zero);
    final second = c.plan('two');
    final secondCancelled = expectLater(second, throwsA(isA<GemmaCancelled>()));
    final third = c.plan('three');
    await firstCancelled;
    await secondCancelled;
    runtime.hold!.complete();
    expect(await third, e02);
    expect(runtime.toolCalls, 2);
    expect(runtime.maxConcurrentJobs, 1);
  });

  test(
    'disable during download ignores late progress and cannot turn back on',
    () async {
      installer.hold = Completer<void>();
      final download = c.downloadAndEnable();
      await Future<void>.delayed(Duration.zero);
      final disabling = c.disable();
      expect(c.toggle, AdvancedToggle.off);
      installer.hold!.complete();
      await download;
      await disabling;
      expect(c.toggle, AdvancedToggle.off);
      expect(c.install, ModelInstallState.notInstalled);
      expect(runtime.loadCalls, 0);
    },
  );

  test('a download that ignores cancellation cannot enable late', () async {
    installer
      ..hold = Completer<void>()
      ..ignoreCancel = true;
    final download = c.downloadAndEnable();
    await Future<void>.delayed(Duration.zero);
    c.cancelDownload();
    installer.hold!.complete();
    await download;
    expect(c.toggle, AdvancedToggle.off);
    expect(c.error, 'Download cancelled.');
    expect(runtime.loadCalls, 0);
    expect(c.install, ModelInstallState.installed);
  });

  test('overlapping enable requests share one load', () async {
    installer.installed = true;
    runtime.loadHold = Completer<void>();
    final first = c.requestEnable();
    final second = c.requestEnable();
    await Future<void>.delayed(Duration.zero);
    expect(runtime.loadCalls, 1);
    runtime.loadHold!.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(runtime.loadCalls, 1);
    expect(c.isOn, isTrue);
  });

  test('disable then re-enable serializes an old load and unload', () async {
    installer.installed = true;
    runtime.loadHold = Completer<void>();
    final first = c.requestEnable();
    await Future<void>.delayed(Duration.zero);
    final disabling = c.disable();
    final second = c.requestEnable();
    runtime.loadHold!.complete();
    await first;
    await disabling;
    await second;
    expect(runtime.events, ['load', 'unload', 'load']);
    expect(c.isOn, isTrue);
    expect(runtime.isLoaded, isTrue);
  });

  test('installation must be verified before activation and load', () async {
    installer.skipInstall = true;
    await c.downloadAndEnable();
    expect(c.install, ModelInstallState.failed);
    expect(c.error, contains('verified'));
    expect(c.toggle, AdvancedToggle.off);
    expect(runtime.loadCalls, 0);
  });

  test('install check failures stay off and allow retry', () async {
    installer.checkError = StateError('unreadable');
    expect(await c.requestEnable(), isFalse);
    expect(c.install, ModelInstallState.failed);
    expect(c.error, contains('unreadable'));
    installer
      ..checkError = null
      ..installed = true;
    expect(await c.requestEnable(), isTrue);
    expect(c.isOn, isTrue);
  });

  test(
    'a refresh finishing after a download does not overwrite installed state',
    () async {
      installer.checkHold = Completer<void>();
      final refresh = c.refreshInstallState();
      installer.checkHold = null;
      await c.downloadAndEnable();
      installer.firstCheck!.complete(false);
      await refresh;
      expect(c.install, ModelInstallState.installed);
      expect(c.isOn, isTrue);
    },
  );

  test('PlanValidator rejects impossible type/payee combinations', () async {
    await turnOn();
    runtime.nextArgs = {
      'shops': ['7-11'],
      'transaction_type': 'transfer',
    };
    await expectLater(
      c.plan('transfers to 7-11'),
      throwsA(
        isA<AdvancedError>().having(
          (e) => e.message,
          'message',
          contains('purchases'),
        ),
      ),
    );
  });

  test('validator canonicalizes semantic sort', () async {
    await turnOn();
    runtime.nextArgs = {'semantic_query': 'camping', 'sort': 'newest'};
    expect((await c.plan('camping')).sort, SortOrder.relevance);
  });

  test(
    'E02 omitted upper bound fails instead of widening the search',
    () async {
      await turnOn();
      runtime.nextArgs = {...e02Args}..remove('amount_max');
      await expectLater(
        c.plan(
          'Find camping purchases last month under THB 3,000 excluding food',
        ),
        throwsA(
          isA<AdvancedError>().having(
            (e) => e.message,
            'message',
            contains('amount'),
          ),
        ),
      );
    },
  );

  for (final args in [
    {'amount_max': 4000},
    {'amount_max': 3000, 'amount_max_inclusive': true},
    {'amount_min': 1, 'amount_max': 3000},
  ]) {
    test('contradictory or extra amount bounds are rejected: $args', () async {
      await turnOn();
      runtime.nextArgs = args;
      await expectLater(
        c.plan('under THB 3,000'),
        throwsA(isA<AdvancedError>()),
      );
    });
  }

  test('both explicit between bounds must be kept', () async {
    await turnOn();
    runtime.nextArgs = {'amount_min': 100, 'amount_min_inclusive': true};
    await expectLater(
      c.plan('between THB 100 and THB 200'),
      throwsA(isA<AdvancedError>()),
    );
    runtime.nextArgs = {
      'amount_min': 100,
      'amount_min_inclusive': true,
      'amount_max': 200,
      'amount_max_inclusive': true,
    };
    final plan = await c.plan('between THB 100 and THB 200');
    expect(plan.minAmount, const AmountBound(10000, inclusive: true));
    expect(plan.maxAmount, const AmountBound(20000, inclusive: true));
  });

  test(
    'explicit follow-up amount validates the merged plan without losing deltas',
    () async {
      await turnOn();
      runtime.nextArgs = {'date_from': '2025-09-01', 'date_to': '2025-09-30'};
      final plan = await c.plan(
        'go back one year, still under THB 3,000',
        current: e02,
      );
      expect(plan.maxAmount, const AmountBound(300000, inclusive: false));
      expect(plan.semanticQuery, 'camping');
      runtime.nextArgs = {
        'clear': ['amount'],
      };
      await expectLater(
        c.plan('still under THB 3,000', current: e02),
        throwsA(isA<AdvancedError>()),
      );
      expect(
        (await c.plan('remove the amount limit', current: e02)).maxAmount,
        isNull,
      );
    },
  );

  test('runtime timeouts and other failures become readable without poisoning the queue', () async {
    await turnOn();
    runtime.nextError = const GemmaTimeout(Duration(seconds: 20));
    await expectLater(
      c.plan('one'),
      throwsA(
        isA<AdvancedError>().having(
          (e) => e.message,
          'message',
          contains('20 s'),
        ),
      ),
    );
    runtime.nextError = StateError('backend stopped');
    await expectLater(
      c.explain('one', kAuthoredTransactions.take(1).toList()),
      throwsA(
        isA<AdvancedError>().having(
          (e) => e.message,
          'message',
          contains('backend stopped'),
        ),
      ),
    );
    runtime.nextArgs = e02Args;
    expect(await c.plan('camping'), e02);
  });

  test('empty explanations never start a runtime job', () async {
    await turnOn();
    await expectLater(c.explain('one', []), throwsA(isA<AdvancedError>()));
    expect(c.jobsStarted, 0);
  });

  test('cancel signal delivers existing and late listeners exactly once', () {
    final signal = GemmaCancelSignal();
    var count = 0;
    signal.onCancel(() {
      count++;
      signal.onCancel(() => count++);
    });
    signal.cancel();
    signal.cancel();
    signal.onCancel(() => count++);
    expect(count, 3);
  });
  test('year ranges are date constraints rather than inferred money', () async {
    await turnOn();
    runtime.nextArgs = {'date_from': '2025-01-01', 'date_to': '2026-09-30'};
    final plan = await c.plan('purchases between 2025 and 2026');
    expect(plan.minAmount, isNull);
    expect(plan.maxAmount, isNull);
    expect(
      plan.dateRange,
      DateRange(bangkokToUtc(2025, 1), bangkokToUtc(2026, 10)),
    );
  });

  test('known numeric payee names cannot become amount constraints', () async {
    await turnOn();
    runtime.nextArgs = {
      'shops': ['7-11'],
    };
    final plan = await c.plan('Show payments under 7-11');
    expect(plan.shopNames, {'7-11'});
    expect(plan.maxAmount, isNull);
  });

  test(
    'date consumption preserves explicit THB amounts that look like years',
    () async {
      await turnOn();
      runtime.nextArgs = {'amount_max': 2025};
      expect(
        (await c.plan('under THB 2025')).maxAmount,
        const AmountBound(202500, inclusive: false),
      );
    },
  );

  test(
    'cancel download while its load is pending keeps the toggle off',
    () async {
      runtime.loadHold = Completer<void>();
      final downloading = c.downloadAndEnable();
      await Future<void>.delayed(Duration.zero);
      expect(c.toggle, AdvancedToggle.enabling);
      c.cancelDownload();
      expect(c.toggle, AdvancedToggle.off);
      runtime.loadHold!.complete();
      await downloading;
      await Future<void>.delayed(Duration.zero);
      expect(c.toggle, AdvancedToggle.off);
      expect(runtime.isLoaded, isFalse);
      expect(c.error, 'Download cancelled.');
    },
  );

  test(
    'enable requested during download does not load a second model',
    () async {
      installer.hold = Completer<void>();
      final downloading = c.downloadAndEnable();
      await Future<void>.delayed(Duration.zero);
      final enabling = c.requestEnable();
      installer.hold!.complete();
      await downloading;
      expect(await enabling, isTrue);
      expect(c.isOn, isTrue);
      expect(runtime.loadCalls, 1);
    },
  );

  test(
    'a slow cancellation must finish before a new conversation starts',
    () async {
      await turnOn();
      runtime
        ..hold = Completer<void>()
        ..cancelHold = Completer<void>()
        ..nextArgs = e02Args;
      final explanation = c.explain(
        'one',
        kAuthoredTransactions.take(1).toList(),
      );
      final cancelled = expectLater(
        explanation,
        throwsA(isA<GemmaCancelled>()),
      );
      await Future<void>.delayed(Duration.zero);
      final planning = c.plan('camping');
      await cancelled;
      runtime.hold!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(runtime.toolCalls, 0);
      runtime.cancelHold!.complete();
      expect(await planning, e02);
      expect(runtime.maxConcurrentJobs, 1);
    },
  );
  test(
    'download action while installed model is loading shares the enable',
    () async {
      installer.installed = true;
      runtime.loadHold = Completer<void>();
      final enabling = c.requestEnable();
      await Future<void>.delayed(Duration.zero);
      final downloading = c.downloadAndEnable();
      runtime.loadHold!.complete();
      await enabling;
      await downloading;
      expect(c.isOn, isTrue);
      expect(runtime.loadCalls, 1);
      expect(installer.installCalls, 0);
    },
  );

  test(
    'dispose cancels current and queued jobs without accepting late results',
    () async {
      await turnOn();
      runtime
        ..ignoreCancel = true
        ..hold = Completer<void>();
      final first = c.explain('one', kAuthoredTransactions.take(1).toList());
      final cancelledFirst = expectLater(first, throwsA(isA<GemmaCancelled>()));
      await Future<void>.delayed(Duration.zero);
      final second = c.explain('two', kAuthoredTransactions.take(1).toList());
      final cancelledSecond = expectLater(
        second,
        throwsA(isA<GemmaCancelled>()),
      );
      c.dispose();
      await cancelledFirst;
      await cancelledSecond;
      runtime.hold!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(runtime.generateCalls, 1);
      expect(runtime.isLoaded, isFalse);
    },
  );
  final bareYearAmounts =
      <(String, Map<String, dynamic>, AmountBound?, AmountBound?)>[
        (
          'under 2000',
          {'amount_max': 2000},
          null,
          const AmountBound(200000, inclusive: false),
        ),
        (
          'over 2025',
          {'amount_min': 2025},
          const AmountBound(202500, inclusive: false),
          null,
        ),
        (
          'at most 2026',
          {'amount_max': 2026, 'amount_max_inclusive': true},
          null,
          const AmountBound(202600, inclusive: true),
        ),
        (
          'exactly 2000',
          {
            'amount_min': 2000,
            'amount_max': 2000,
            'amount_min_inclusive': true,
            'amount_max_inclusive': true,
          },
          const AmountBound(200000, inclusive: true),
          const AmountBound(200000, inclusive: true),
        ),
      ];
  for (final (query, args, min, max) in bareYearAmounts) {
    test('bare year-like money rejects a missing bound: $query', () async {
      await turnOn();
      runtime.nextArgs = {};
      await expectLater(
        c.plan(query),
        throwsA(
          isA<AdvancedError>().having(
            (e) => e.message,
            'message',
            contains('amount'),
          ),
        ),
      );
    });
    test('bare year-like money rejects a changed bound: $query', () async {
      await turnOn();
      runtime.nextArgs = {
        ...args,
        if (min != null) 'amount_min': 1999,
        if (max != null) 'amount_max': 2027,
      };
      await expectLater(c.plan(query), throwsA(isA<AdvancedError>()));
    });
    test(
      'bare year-like money accepts the correct bound alongside dates: $query',
      () async {
        await turnOn();
        runtime.nextArgs = {
          ...args,
          'date_from': '2025-01-01',
          'date_to': '2025-12-31',
        };
        final plan = await c.plan('$query in 2025');
        expect(plan.minAmount, min);
        expect(plan.maxAmount, max);
        expect(
          plan.dateRange,
          DateRange(bangkokToUtc(2025, 1), bangkokToUtc(2026, 1)),
        );
      },
    );
  }

  test('year-like upper amount rejects an unrequested lower bound', () async {
    await turnOn();
    runtime.nextArgs = {'amount_min': 1, 'amount_max': 2000};
    await expectLater(c.plan('under 2000'), throwsA(isA<AdvancedError>()));
  });

  test('ISO date operands stay dates despite a money-like operator', () async {
    await turnOn();
    runtime.nextArgs = {'date_to': '2025-02-01'};
    final plan = await c.plan('transactions under 2025-02-01');
    expect(plan.minAmount, isNull);
    expect(plan.maxAmount, isNull);
    expect(plan.dateRange!.end, bangkokToUtc(2025, 2, 2));
  });

  for (final ignoreCancel in [true, false]) {
    test(
      'fresh enable after cancelled download follows current intent: ignoreCancel=$ignoreCancel',
      () async {
        installer
          ..hold = Completer<void>()
          ..ignoreCancel = ignoreCancel;
        final download = c.downloadAndEnable();
        await Future<void>.delayed(Duration.zero);
        final disabling = c.disable();
        final enabling = c.requestEnable();
        final duplicateEnable = c.requestEnable();
        expect(c.toggle, AdvancedToggle.off);
        expect(installer.installCalls, 1);
        expect(runtime.loadCalls, 0);
        installer.hold!.complete();
        await download;
        await disabling;
        expect(await enabling, ignoreCancel);
        expect(await duplicateEnable, ignoreCancel);
        expect(c.isOn, ignoreCancel);
        expect(runtime.loadCalls, ignoreCancel ? 1 : 0);
        expect(installer.installCalls, 1);
        if (ignoreCancel) {
          expect(c.error, isNull);
          expect(runtime.events, ['unload', 'load']);
        } else {
          expect(c.install, ModelInstallState.notInstalled);
        }
      },
    );
  }

  test(
    'year-like monetary ranges with a currency suffix stay amounts',
    () async {
      await turnOn();
      runtime.nextArgs = {
        'amount_min': 2000,
        'amount_max': 2025,
        'amount_min_inclusive': true,
        'amount_max_inclusive': true,
      };
      final plan = await c.plan('between 2000 and 2025 baht');
      expect(plan.minAmount, const AmountBound(200000, inclusive: true));
      expect(plan.maxAmount, const AmountBound(202500, inclusive: true));
    },
  );
  for (final punctuation in ['.', ', excluding food']) {
    test(
      'genuine year ranges remain dates before punctuation: $punctuation',
      () async {
        await turnOn();
        runtime.nextArgs = {'date_from': '2025-01-01', 'date_to': '2026-09-30'};
        final plan = await c.plan(
          'purchases between 2025 and 2026$punctuation',
        );
        expect(plan.minAmount, isNull);
        expect(plan.maxAmount, isNull);
      },
    );
  }
}
