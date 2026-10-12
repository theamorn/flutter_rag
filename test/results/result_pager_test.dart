import 'dart:async';

import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/results/result_pager.dart';
import 'package:flutter_rag/results/result_source.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction row(String id) => Transaction(
      id: id,
      occurredAt: DateTime.utc(2026),
      shopName: 'Shop',
      type: TransactionType.purchase,
      amountMinor: 100,
      category: Category.food,
    );

/// Serves [total] rows named `<prefix>N`. With [manual], each fetch waits
/// until the test completes it.
class FakeSource implements ResultSource {
  FakeSource(this.total, {this.prefix = 't', this.manual = false});

  final int total;
  final String prefix;
  final bool manual;
  final calls = <(int, int)>[];
  final pending = <Completer<PageResult>>[];
  Object? failNext;

  PageResult _page(int offset, int limit) {
    final end = (offset + limit).clamp(0, total);
    return PageResult(
      [for (var i = offset; i < end; i++) row('$prefix$i')],
      reachedEnd: end >= total,
    );
  }

  @override
  Future<PageResult> fetch(int offset, int limit) {
    calls.add((offset, limit));
    final fail = failNext;
    failNext = null;
    if (fail != null) return Future.error(fail);
    if (!manual) return Future.value(_page(offset, limit));
    final c = Completer<PageResult>();
    pending.add(c);
    return c.future;
  }

  void completeNext() {
    final (offset, limit) = calls[calls.length - pending.length];
    pending.removeAt(0).complete(_page(offset, limit));
  }
}

void main() {
  test('first page of 100, then pages of 20, then a final partial page', () async {
    final pager = ResultPager();
    final source = FakeSource(135);
    await pager.start(source);
    expect(pager.items.length, 100);
    expect(pager.status, PagerStatus.ready);
    await pager.loadMore();
    expect(pager.items.length, 120);
    await pager.loadMore();
    expect(pager.items.length, 135);
    expect(pager.status, PagerStatus.end);
    await pager.loadMore(); // no-op at the end
    expect(source.calls, [(0, 100), (100, 20), (120, 20)]);
  });

  test('only one page request at a time', () async {
    final pager = ResultPager();
    final source = FakeSource(300, manual: true);
    final first = pager.start(source);
    source.completeNext();
    await first;
    final a = pager.loadMore();
    final b = pager.loadMore(); // ignored while loading
    expect(source.calls.length, 2);
    source.completeNext();
    await Future.wait([a, b]);
    expect(pager.items.length, 120);
  });

  test('a stale first page is discarded when a new search starts', () async {
    final pager = ResultPager();
    final slow = FakeSource(300, prefix: 'old', manual: true);
    final fast = FakeSource(5, prefix: 'new');
    final stale = pager.start(slow);
    await pager.start(fast);
    slow.completeNext();
    await stale;
    expect(pager.items.map((t) => t.id), ['new0', 'new1', 'new2', 'new3', 'new4']);
    expect(pager.status, PagerStatus.end);
  });

  test('a stale next page is discarded too', () async {
    final pager = ResultPager();
    final source = FakeSource(300, manual: true);
    final first = pager.start(source);
    source.completeNext();
    await first;
    final more = pager.loadMore();
    await pager.start(FakeSource(3, prefix: 'new'));
    source.completeNext();
    await more;
    expect(pager.items.map((t) => t.id), ['new0', 'new1', 'new2']);
  });

  test('a failed next page keeps the rows and can be retried', () async {
    final pager = ResultPager();
    final source = FakeSource(150);
    await pager.start(source);
    source.failNext = Exception('offline');
    await pager.loadMore();
    expect(pager.status, PagerStatus.nextPageError);
    expect(pager.items.length, 100);
    await pager.retry();
    expect(pager.items.length, 120);
    expect(pager.status, PagerStatus.ready);
  });

  test('a failed first page can be retried', () async {
    final pager = ResultPager();
    final source = FakeSource(10)..failNext = Exception('boom');
    await pager.start(source);
    expect(pager.status, PagerStatus.firstPageError);
    await pager.retry();
    expect(pager.items.length, 10);
    expect(pager.status, PagerStatus.end);
  });

  test('rows are de-duplicated by id', () async {
    final pager = ResultPager();
    await pager.start(_Repeating());
    await pager.loadMore();
    expect(pager.items.map((t) => t.id).toSet().length, pager.items.length);
  });
}

class _Repeating implements ResultSource {
  @override
  Future<PageResult> fetch(int offset, int limit) async =>
      PageResult([for (var i = 0; i < limit; i++) row('same${i % 50}')], reachedEnd: false);
}
