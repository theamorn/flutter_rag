import 'package:flutter/material.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/results/result_pager.dart';
import 'package:flutter_rag/results/result_source.dart';
import 'package:flutter_rag/ui/transaction_list.dart';
import 'package:flutter_rag/ui/transaction_tile.dart';
import 'package:flutter_test/flutter_test.dart';

class CountingSource implements ResultSource {
  CountingSource(this.total);

  final int total;
  int calls = 0;

  @override
  Future<PageResult> fetch(int offset, int limit) async {
    calls++;
    final end = (offset + limit).clamp(0, total);
    return PageResult([
      for (var i = offset; i < end; i++)
        Transaction(
          id: 't$i',
          occurredAt: DateTime.utc(2026, 9, 1),
          shopName: 'Shop $i',
          type: TransactionType.purchase,
          amountMinor: 1000,
          category: Category.food,
        ),
    ], reachedEnd: end >= total);
  }
}

void main() {
  testWidgets('scrolling near the bottom loads more until the end', (tester) async {
    final pager = ResultPager();
    final source = CountingSource(135);
    await pager.start(source);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TransactionList(pager: pager, onOpen: (_) {})),
    ));
    expect(find.byType(TransactionTile), findsWidgets);
    await tester.scrollUntilVisible(find.text('End of results'), 600);
    expect(pager.items.length, 135);
    expect(source.calls, 3);
  });

  testWidgets('empty results say so', (tester) async {
    final pager = ResultPager();
    await pager.start(CountingSource(0));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TransactionList(pager: pager, onOpen: (_) {})),
    ));
    expect(find.text('No matching transactions'), findsOneWidget);
  });
}
