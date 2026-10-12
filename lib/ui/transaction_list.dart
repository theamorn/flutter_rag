import 'package:flutter/material.dart';

import '../core/transaction.dart';
import '../results/result_pager.dart';
import 'transaction_tile.dart';

/// Lazy list over a [ResultPager]: loads the next page near the bottom and
/// jumps back to the top when a new search starts.
class TransactionList extends StatefulWidget {
  const TransactionList({super.key, required this.pager, required this.onOpen});

  final ResultPager pager;
  final void Function(Transaction transaction) onOpen;

  @override
  State<TransactionList> createState() => _TransactionListState();
}

class _TransactionListState extends State<TransactionList> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    widget.pager.addListener(_onPagerChanged);
  }

  @override
  void didUpdateWidget(TransactionList old) {
    super.didUpdateWidget(old);
    if (old.pager != widget.pager) {
      old.pager.removeListener(_onPagerChanged);
      widget.pager.addListener(_onPagerChanged);
    }
  }

  void _onPagerChanged() {
    if (widget.pager.status == PagerStatus.loadingFirst && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  void _maybeLoadMore() {
    if (_scroll.position.extentAfter < 600) widget.pager.loadMore();
  }

  @override
  void dispose() {
    widget.pager.removeListener(_onPagerChanged);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.pager,
    builder: (context, _) {
      final pager = widget.pager;
      final items = pager.items;
      if (pager.status == PagerStatus.loadingFirst ||
          pager.status == PagerStatus.idle) {
        return const Center(child: CircularProgressIndicator());
      }
      if (pager.status == PagerStatus.firstPageError) {
        final scheme = Theme.of(context).colorScheme;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, color: scheme.error),
              const SizedBox(height: 8),
              Text(
                "Couldn't load transactions.",
                style: TextStyle(color: scheme.onSurface),
              ),
              TextButton(onPressed: pager.retry, child: const Text('Retry')),
            ],
          ),
        );
      }
      if (items.isEmpty) {
        final scheme = Theme.of(context).colorScheme;
        return Center(
          child: Text(
            'No matching transactions',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      return ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
        itemCount: items.length + 1,
        itemBuilder: (context, i) {
          if (i == items.length) return _Footer(pager: pager);
          final t = items[i];
          return TransactionTile(
            key: ValueKey(t.id),
            transaction: t,
            onTap: () => widget.onOpen(t),
          );
        },
      );
    },
  );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.pager});

  final ResultPager pager;

  @override
  Widget build(BuildContext context) => switch (pager.status) {
    PagerStatus.loadingMore => const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator()),
    ),
    PagerStatus.nextPageError => ListTile(
      title: const Text("Couldn't load more."),
      trailing: TextButton(onPressed: pager.retry, child: const Text('Retry')),
    ),
    PagerStatus.end => Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          'End of results',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    ),
    _ => const SizedBox(height: 48),
  };
}
