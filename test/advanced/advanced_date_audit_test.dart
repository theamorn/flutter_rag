import 'package:flutter_rag/advanced/advanced_controller.dart';
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gemma.dart';

void main() {
  late FakeGemmaRuntime runtime;
  late AdvancedController controller;
  setUp(() async {
    runtime = FakeGemmaRuntime();
    controller = AdvancedController(installer: FakeGemmaInstaller()..installed = true,
      runtime: runtime, directory: PayeeDirectory(shops: ['7-11'], people: [...kFamilyGroup]));
    await controller.requestEnable();
  });
  tearDown(() async { await controller.disable(); controller.dispose(); });
  test('last month omitted by real E02 response is rejected without repair', () async {
    runtime.nextArgs = {'amount_max': 3000, 'amount_max_inclusive': false,
      'exclude_categories': ['food'], 'transaction_type': 'purchase', 'semantic_query': 'camping'};
    await expectLater(controller.plan('Find things I bought for camping last month, under THB 3,000, excluding food.'),
      throwsA(isA<AdvancedError>().having((e) => e.message, 'message', contains('requested dates'))));
  });
  test('wrong supported month is rejected', () async {
    runtime.nextArgs = {'date_from': '2026-08-01', 'date_to': '2026-08-31'};
    await expectLater(controller.plan('payments last month'), throwsA(isA<AdvancedError>()));
  });
  test('known numeric payee is protected before date audit', () async {
    runtime.nextArgs = {'shops': ['7-11'], 'date_from': '2026-09-01', 'date_to': '2026-09-30'};
    expect((await controller.plan('my 7-11 payments last month')).dateRange, bangkokMonth(2026,9));
  });
  test('operator-qualified year-like money is not a date', () async {
    runtime.nextArgs = {'amount_max': 2025};
    expect((await controller.plan('under 2025')).dateRange, isNull);
  });
  test('independent absolute follow-up dates are audited against merged plan', () async {
    runtime.nextArgs = {'date_from': '2026-09-01', 'date_to': '2026-09-30'};
    final current = await controller.plan('last month');
    runtime.nextArgs = {};
    await expectLater(controller.plan('last year instead',current:current), throwsA(isA<AdvancedError>()));
    runtime.nextArgs = {'date_from': '2025-01-01', 'date_to': '2025-12-31'};
    expect((await controller.plan('last year instead',current:current)).dateRange, bangkokYear(2025));
  });
  test('E29 cannot clear a supported date shift requested by user', () async {
    runtime.nextArgs = {'clear': ['dates']};
    await expectLater(controller.plan('Same purchases, but go back one year and include the month before it too',
      current:SearchPlan(dateRange:bangkokMonth(2026,9))), throwsA(isA<AdvancedError>()));
    runtime.nextArgs = {'date_from':'2025-08-01','date_to':'2025-09-30'};
    expect((await controller.plan('Same purchases, but go back one year and include the month before it too',
      current:SearchPlan(dateRange:bangkokMonth(2026,9)))).dateRange,
      DateRange(bangkokMonth(2025,8).start,bangkokMonth(2025,9).end));
  });
  test('single Mom payee cannot widen to family', () async {
    runtime.nextArgs = {'family':true,'transaction_type':'transfer'};
    await expectLater(controller.plan('Show transfers to Mom'), throwsA(isA<AdvancedError>()));
  });
  test('explicit family accepts all family members', () async {
    runtime.nextArgs = {'family':true,'transaction_type':'transfer'};
    expect((await controller.plan('Show transfers to my family')).personNames,kFamilyGroup.toSet());
  });

  group('foreign-currency amounts are rejected, never silently applied as THB', () {
    for (final (query, args) in [
      ('Payments over 100 dollars last year', {'amount_min': 100, 'date_from': '2025-01-01', 'date_to': '2025-12-31'}),
      ('coffee under \$50', {'amount_max': 50, 'semantic_query': 'coffee'}),
    ]) {
      test(query, () async {
        runtime.nextArgs = args;
        await expectLater(
          controller.plan(query),
          throwsA(isA<AdvancedError>().having((e) => e.message, 'message', contains('THB'))),
        );
      });
    }

    test('a plan that adds no amount is accepted (the note stays visible)', () async {
      runtime.nextArgs = {'semantic_query': 'coffee'};
      final plan = await controller.plan('coffee under \$50');
      expect(plan.maxAmount, isNull);
      expect(plan.minAmount, isNull);
    });

    test('an unchanged amount from the current plan is not blamed on the model', () async {
      runtime.nextArgs = {'semantic_query': 'coffee'};
      final current = SearchPlan(maxAmount: const AmountBound(300000, inclusive: false));
      final plan = await controller.plan('same but under \$50', current: current);
      expect(plan.maxAmount, current.maxAmount);
    });
  });
}
