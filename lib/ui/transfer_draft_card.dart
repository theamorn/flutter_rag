import 'package:flutter/material.dart';

import '../advanced/transfer_drafter.dart';
import '../core/bangkok_time.dart';
import '../core/money.dart';

/// Displays a repeat-transfer draft produced by the Code -> LLM -> Post-Hook
/// pipeline: the recipient and satang amount come deterministically from the
/// source SQLite row, while the updated memo comes from Gemma's `draft_transfer`
/// tool call after post-hook validation.
class TransferDraftCard extends StatefulWidget {
  const TransferDraftCard({
    super.key,
    required this.draft,
    required this.onOpen,
    required this.onDismiss,
  });

  final TransferDraft draft;
  final void Function(String txnId) onOpen;
  final VoidCallback onDismiss;

  @override
  State<TransferDraftCard> createState() => _TransferDraftCardState();
}

class _TransferDraftCardState extends State<TransferDraftCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Scrollable.maybeOf(context)?.position.ensureVisible(
          context.findRenderObject()!,
          alignment: 0,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.draft;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 4,
      shadowColor: theme.colorScheme.primary.withValues(alpha: 0.28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.send_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Repeat transfer draft (Gemma 4 + post-hook)',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Dismiss draft',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onDismiss,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Send ${formatThb(d.amountMinor)} to ${d.recipient}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${d.category.label} · amount & recipient verified from SQLite (${formatBangkokDate(d.sourceOccurredAt)})',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('New memo: "${d.newMemo}"'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ActionChip(
                        label: Text(d.sourceTxnId),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: () => widget.onOpen(d.sourceTxnId),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('view-transfer-draft-json'),
                        onPressed: () => showTransferDraftDialog(
                          context,
                          draft: d,
                          onOpen: widget.onOpen,
                          onDismiss: widget.onDismiss,
                        ),
                        icon: const Icon(Icons.data_object, size: 16),
                        label: const Text('View JSON'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        key: const ValueKey('confirm-transfer-draft'),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Demo transfer confirmed: ${formatThb(d.amountMinor)} '
                                'to ${d.recipient} ("${d.newMemo}").',
                              ),
                            ),
                          );
                          widget.onDismiss();
                        },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Confirm transfer'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a popup dialog displaying both Gemma's `draft_transfer` tool call JSON
/// and the post-hook-verified API request JSON ready to submit.
Future<void> showTransferDraftDialog(
  BuildContext context, {
  required TransferDraft draft,
  required void Function(String txnId) onOpen,
  required VoidCallback onDismiss,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        key: const ValueKey('transfer-draft-dialog'),
        title: Row(
          children: [
            Icon(Icons.data_object, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Draft Transfer JSON',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send ${formatThb(draft.amountMinor)} to ${draft.recipient}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'New memo: "${draft.newMemo}"',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              ActionChip(
                label: Text('Source: ${draft.sourceTxnId}'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  onOpen(draft.sourceTxnId);
                },
              ),
              const SizedBox(height: 12),
              Text(
                '1. Gemma Tool Call (draft_transfer)',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Gemma selects the source row and adapts the memo for October 2026 (no amount field allowed):',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              _JsonCodeBlock(jsonText: draft.prettyGemmaToolCallJson),
              const SizedBox(height: 12),
              Text(
                '2. Verified API Payload (Post-Hook Output)',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Deterministic post-hook cross-checks the ID & recipient and copies exact satang (${draft.amountMinor}) from SQLite before submitting to API:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              _JsonCodeBlock(jsonText: draft.prettyApiRequestJson),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            key: const ValueKey('dialog-submit-transfer-api'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Submitted POST /v1/transfers/draft: ${formatThb(draft.amountMinor)} '
                    'to ${draft.recipient} ("${draft.newMemo}").',
                  ),
                ),
              );
              onDismiss();
            },
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Submit to API'),
          ),
        ],
      );
    },
  );
}

class _JsonCodeBlock extends StatelessWidget {
  const _JsonCodeBlock({required this.jsonText});

  final String jsonText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: SelectableText(
        jsonText,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}
