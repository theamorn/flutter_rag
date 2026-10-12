import 'package:flutter/material.dart';
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_rag/ui/plan_chips.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('amount chip labels', () {
    expect(amountChipLabel(null, const AmountBound(300000, inclusive: false)), '< THB 3,000.00');
    expect(amountChipLabel(const AmountBound(1000000, inclusive: false), null), '> THB 10,000.00');
    expect(
      amountChipLabel(const AmountBound(100000, inclusive: true), const AmountBound(130000, inclusive: true)),
      'THB 1,000.00 – THB 1,300.00',
    );
  });

  testWidgets('one chip per active filter; delete and add edit the plan', (tester) async {
    SearchPlan? changed;
    final plan = SearchPlan(
      dateRange: bangkokMonth(2026, 9),
      maxAmount: const AmountBound(300000, inclusive: false),
      excludeCategories: const {Category.food},
      personNames: kFamilyGroup.toSet(),
      semanticQuery: 'camping',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PlanChips(plan: plan, onChanged: (p) => changed = p)),
    ));
    expect(find.text('1 Sep 2026 – 30 Sep 2026'), findsOneWidget);
    expect(find.text('< THB 3,000.00'), findsOneWidget);
    expect(find.text('Not food'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('Meaning: "camping"'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove < THB 3,000.00'));
    expect(changed!.maxAmount, isNull);
    expect(changed!.dateRange, plan.dateRange);

    await tester.tap(find.text('Add filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Has memo'));
    await tester.pumpAndSettle();
    expect(changed!.hasMemo, isTrue);
  });
}
