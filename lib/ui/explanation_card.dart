import 'package:flutter/material.dart';

import '../advanced/explainer.dart';

/// The grounded explanation: validated text plus tappable source chips.
///
/// It has no height of its own: the search screen places it inside the capped,
/// scrollable header, so a long answer scrolls there and the result list below
/// keeps its share of a phone screen. A new card scrolls itself into view.
class ExplanationCard extends StatefulWidget {
  const ExplanationCard({
    super.key,
    required this.explanation,
    required this.onOpen,
    required this.onDismiss,
  });

  final Explanation explanation;
  final void Function(String txnId) onOpen;
  final VoidCallback onDismiss;

  @override
  State<ExplanationCard> createState() => _ExplanationCardState();
}

class _ExplanationCardState extends State<ExplanationCard> {
  @override
  void initState() {
    super.initState();
    // Show the start of a new answer even when the header is scrolled away.
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
    final e = widget.explanation;
    final removed = e.invalidIds.length;
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
                  Icons.auto_awesome,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Explanation (Gemma 4, on device)',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Dismiss',
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
                  if (!e.isUsable)
                    const Text(
                      'Explanation unavailable: the model did not cite the transactions shown.',
                    )
                  else
                    Text(e.text),
                  if (removed > 0)
                    Text(
                      'Removed $removed reference${removed == 1 ? '' : 's'} to transactions that were not shown.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  if (e.isUsable)
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final id in e.citedIds)
                          ActionChip(
                            label: Text(id),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onPressed: () => widget.onOpen(id),
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
