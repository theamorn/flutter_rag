import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../core/bangkok_time.dart';
import '../core/categories.dart';
import '../core/money.dart';
import '../core/payees.dart';
import '../core/transaction.dart';
import '../search/search_plan.dart';

/// Chip text for the amount bounds, e.g. `< THB 3,000.00`.
String amountChipLabel(AmountBound? min, AmountBound? max) {
  String lower(AmountBound b) => '${b.inclusive ? '≥' : '>'} ${formatThb(b.minor)}';
  String upper(AmountBound b) => '${b.inclusive ? '≤' : '<'} ${formatThb(b.minor)}';
  if (min != null && max != null) {
    if (min.inclusive && max.inclusive) {
      return '${formatThb(min.minor)} – ${formatThb(max.minor)}';
    }
    return '${lower(min)} and ${upper(max)}';
  }
  if (max != null) return upper(max);
  if (min != null) return lower(min);
  return '';
}

String _sortLabel(SortOrder sort) => switch (sort) {
      SortOrder.oldest => 'Oldest first',
      SortOrder.amountDesc => 'Biggest first',
      SortOrder.amountAsc => 'Smallest first',
      SortOrder.newest => 'Newest first',
      SortOrder.relevance => 'Most relevant first',
    };

/// One editable chip per active filter (spec §11.4).
class PlanChips extends StatelessWidget {
  const PlanChips({super.key, required this.plan, required this.onChanged});

  final SearchPlan plan;
  final ValueChanged<SearchPlan> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = plan;
    final family = p.personNames.isNotEmpty && setEquals(p.personNames, kFamilyGroup.toSet());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(spacing: 8, runSpacing: 4, children: [
        if (p.dateRange case final range?)
          _Chip(Icons.event, formatDateRange(range),
              onDeleted: () => onChanged(p.copyWith(dateRange: null)),
              onTap: () => _editDates(context)),
        if (p.minAmount != null || p.maxAmount != null)
          _Chip(Icons.payments_outlined, amountChipLabel(p.minAmount, p.maxAmount),
              onDeleted: () => onChanged(p.copyWith(minAmount: null, maxAmount: null)),
              onTap: () => _editAmount(context)),
        for (final c in p.includeCategories)
          _Chip(Icons.category_outlined, c.label,
              onDeleted: () => onChanged(p.copyWith(includeCategories: {...p.includeCategories}..remove(c))),
              onTap: () => _editCategories(context)),
        for (final c in p.excludeCategories)
          _Chip(Icons.block, 'Not ${c.label.toLowerCase()}',
              onDeleted: () => onChanged(p.copyWith(excludeCategories: {...p.excludeCategories}..remove(c))),
              onTap: () => _editCategories(context)),
        if (family)
          _Chip(Icons.family_restroom, 'Family',
              onDeleted: () => onChanged(p.copyWith(personNames: const {})))
        else
          for (final name in p.personNames)
            _Chip(Icons.person_outline, name,
                onDeleted: () => onChanged(p.copyWith(personNames: {...p.personNames}..remove(name)))),
        for (final name in p.shopNames)
          _Chip(Icons.storefront_outlined, name,
              onDeleted: () => onChanged(p.copyWith(shopNames: {...p.shopNames}..remove(name)))),
        if (p.transactionType case final type?)
          _Chip(Icons.swap_horiz, type == TransactionType.purchase ? 'Purchases' : 'Transfers',
              onDeleted: () => onChanged(p.copyWith(transactionType: null))),
        if (p.hasMemo case final hasMemo?)
          _Chip(Icons.sticky_note_2_outlined, hasMemo ? 'Has memo' : 'No memo',
              onDeleted: () => onChanged(p.copyWith(hasMemo: null))),
        if (p.semanticQuery case final q?)
          _Chip(Icons.auto_awesome_outlined, 'Meaning: "$q"',
              onDeleted: () => onChanged(p.copyWith(semanticQuery: null)),
              onTap: () => _editMeaning(context)),
        if (p.sort case SortOrder.oldest || SortOrder.amountDesc || SortOrder.amountAsc)
          _Chip(Icons.sort, _sortLabel(p.sort),
              onDeleted: () => onChanged(p.copyWith(sort: SortOrder.newest))),
        if (p.limit case final n?)
          _Chip(Icons.filter_list, 'Top $n', onDeleted: () => onChanged(p.copyWith(limit: null))),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: const Text('Add filter'),
          onPressed: () => _addFilter(context),
        ),
      ]),
    );
  }

  Future<void> _editDates(BuildContext context) async {
    DateTime local(DateTime utc) {
      final w = toBangkokWallClock(utc);
      return DateTime(w.year, w.month, w.day);
    }

    final first = DateTime(2023, 10, 1);
    final last = DateTime(2026, 9, 30);
    final current = plan.dateRange;
    DateTimeRange? initial;
    if (current != null) {
      final s = local(current.start);
      final e = local(current.end.subtract(const Duration(milliseconds: 1)));
      if (!s.isBefore(first) && !e.isAfter(last)) {
        initial = DateTimeRange(start: s, end: e);
      }
    }
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      currentDate: local(kReferenceNow),
      initialDateRange: initial,
    );
    if (picked == null) return;
    onChanged(plan.copyWith(
      dateRange: DateRange(
        bangkokToUtc(picked.start.year, picked.start.month, picked.start.day),
        bangkokToUtc(picked.end.year, picked.end.month, picked.end.day + 1),
      ),
    ));
  }

  Future<void> _editAmount(BuildContext context) async {
    final result = await showDialog<(AmountBound?, AmountBound?)>(
      context: context,
      builder: (_) => _AmountDialog(min: plan.minAmount, max: plan.maxAmount),
    );
    if (result == null) return;
    onChanged(plan.copyWith(minAmount: result.$1, maxAmount: result.$2));
  }

  Future<void> _editCategories(BuildContext context) async {
    final result = await showDialog<(Set<Category>, Set<Category>)>(
      context: context,
      builder: (_) => _CategoryDialog(
          include: plan.includeCategories, exclude: plan.excludeCategories),
    );
    if (result == null) return;
    onChanged(plan.copyWith(includeCategories: result.$1, excludeCategories: result.$2));
  }

  Future<void> _editMeaning(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _MeaningDialog(initial: plan.semanticQuery ?? ''),
    );
    if (result == null) return;
    final text = result.trim();
    onChanged(plan.copyWith(semanticQuery: text.isEmpty ? null : text));
  }

  Future<void> _addFilter(BuildContext context) async {
    const options = [
      ('date', Icons.event, 'Date range'),
      ('amount', Icons.payments_outlined, 'Amount'),
      ('category', Icons.category_outlined, 'Category'),
      ('purchase', Icons.storefront_outlined, 'Purchases only'),
      ('transfer', Icons.person_outline, 'Transfers only'),
      ('memo', Icons.sticky_note_2_outlined, 'Has memo'),
      ('nomemo', Icons.notes, 'No memo'),
    ];
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (key, icon, label) in options)
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.pop(sheet, key),
            ),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'date':
        await _editDates(context);
      case 'amount':
        await _editAmount(context);
      case 'category':
        await _editCategories(context);
      case 'purchase':
        onChanged(plan.copyWith(transactionType: TransactionType.purchase));
      case 'transfer':
        onChanged(plan.copyWith(transactionType: TransactionType.transfer));
      case 'memo':
        onChanged(plan.copyWith(hasMemo: true));
      case 'nomemo':
        onChanged(plan.copyWith(hasMemo: false));
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.label, {required this.onDeleted, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onDeleted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InputChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onPressed: onTap,
        onDeleted: onDeleted,
        deleteButtonTooltipMessage: 'Remove $label',
      );
}

/// Owns its controller so it outlives the dialog's exit animation.
class _MeaningDialog extends StatefulWidget {
  const _MeaningDialog({required this.initial});

  final String initial;

  @override
  State<_MeaningDialog> createState() => _MeaningDialogState();
}

class _MeaningDialogState extends State<_MeaningDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Search by meaning'),
        content: TextField(controller: _controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('Apply'),
          ),
        ],
      );
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({this.min, this.max});

  final AmountBound? min;
  final AmountBound? max;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _min = TextEditingController(text: _text(widget.min));
  late final _max = TextEditingController(text: _text(widget.max));
  late bool _minInclusive = widget.min?.inclusive ?? true;
  late bool _maxInclusive = widget.max?.inclusive ?? false;
  String? _error;

  static String _text(AmountBound? b) =>
      b == null ? '' : (b.minor / 100).toStringAsFixed(2);

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  AmountBound? _parse(TextEditingController c, bool inclusive) {
    if (c.text.trim().isEmpty) return null;
    final minor = parseBahtToMinor(c.text);
    if (minor == null) throw FormatException(c.text);
    return AmountBound(minor, inclusive: inclusive);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Amount (THB)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _min, decoration: const InputDecoration(labelText: 'From'), keyboardType: TextInputType.number),
          CheckboxListTile(
            value: _minInclusive,
            onChanged: (v) => setState(() => _minInclusive = v ?? true),
            title: const Text('Include this amount'),
          ),
          TextField(controller: _max, decoration: const InputDecoration(labelText: 'To'), keyboardType: TextInputType.number),
          CheckboxListTile(
            value: _maxInclusive,
            onChanged: (v) => setState(() => _maxInclusive = v ?? false),
            title: const Text('Include this amount'),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              try {
                Navigator.pop(context, (_parse(_min, _minInclusive), _parse(_max, _maxInclusive)));
              } on FormatException catch (e) {
                setState(() => _error = 'Not an amount: "${e.message}"');
              }
            },
            child: const Text('Apply'),
          ),
        ],
      );
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.include, required this.exclude});

  final Set<Category> include;
  final Set<Category> exclude;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  // 0 = any, 1 = include, 2 = exclude
  late final Map<Category, int> _mode = {
    for (final c in Category.values)
      c: widget.include.contains(c) ? 1 : (widget.exclude.contains(c) ? 2 : 0),
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Categories'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final c in Category.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(c.label)),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Any')),
                      ButtonSegment(value: 1, label: Text('Only')),
                      ButtonSegment(value: 2, label: Text('Not')),
                    ],
                    selected: {_mode[c]!},
                    onSelectionChanged: (s) => setState(() => _mode[c] = s.single),
                  ),
                ]),
              ),
          ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              {for (final e in _mode.entries) if (e.value == 1) e.key},
              {for (final e in _mode.entries) if (e.value == 2) e.key},
            )),
            child: const Text('Apply'),
          ),
        ],
      );
}
