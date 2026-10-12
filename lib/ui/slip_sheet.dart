import 'package:flutter/material.dart';

import '../core/bangkok_time.dart';
import '../core/money.dart';
import '../core/transaction.dart';
import 'transaction_tile.dart';

Future<void> showTransactionSlip(
  BuildContext context, {
  required Transaction transaction,
  required Future<Transaction> Function(String id, String? memo) onSaveMemo,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => SlipSheet(transaction: transaction, onSaveMemo: onSaveMemo),
);

/// "Demo transaction slip": every field comes from the original record.
class SlipSheet extends StatefulWidget {
  const SlipSheet({
    super.key,
    required this.transaction,
    required this.onSaveMemo,
  });

  final Transaction transaction;
  final Future<Transaction> Function(String id, String? memo) onSaveMemo;

  @override
  State<SlipSheet> createState() => _SlipSheetState();
}

class _SlipSheetState extends State<SlipSheet> {
  late Transaction _t = widget.transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _t;
    final purchase = t.type == TransactionType.purchase;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Demo transaction slip',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Synthetic demo data',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                formatThb(t.amountMinor),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: categoryAccent(t.category),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _Field(purchase ? 'Shop' : 'Paid to', t.payeeName),
            _Field('Type', purchase ? 'Purchase' : 'Transfer'),
            _Field('Currency', t.currency),
            _Field(
              'Date and time',
              '${formatBangkokDateTime(t.occurredAt)} (Bangkok)',
            ),
            _Field('Category', t.category.label),
            if (t.description != null) _Field('Description', t.description!),
            _Field('Reference', t.id),
            if (t.memo != null)
              _Field('Memo', t.memo!, key: const Key('slip-memo')),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _editMemo,
                  icon: const Icon(Icons.edit_note),
                  label: Text(t.memo == null ? 'Add memo' : 'Edit memo'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMemo() async {
    // null = cancel, '' = clear, otherwise the new text.
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _MemoDialog(initial: _t.memo ?? ''),
    );
    if (result == null) return;
    final updated = await widget.onSaveMemo(_t.id, result);
    if (mounted) setState(() => _t = updated);
  }
}

/// Owns its controller so it is disposed only after the dialog's exit
/// animation has finished (disposing right after `showDialog` returns makes
/// the closing TextField use a disposed controller).
class _MemoDialog extends StatefulWidget {
  const _MemoDialog({required this.initial});

  final String initial;

  @override
  State<_MemoDialog> createState() => _MemoDialogState();
}

class _MemoDialogState extends State<_MemoDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Memo'),
    content: TextField(controller: _controller, autofocus: true, maxLines: 3),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, ''),
        child: const Text('Clear'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
