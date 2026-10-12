import 'package:flutter/material.dart';

import '../core/bangkok_time.dart';
import '../core/categories.dart';
import '../core/money.dart';
import '../core/transaction.dart';

/// Stable highlight for each category, used on the list and the slip.
Color categoryAccent(Category category) => switch (category) {
  Category.bill => const Color(0xFF1D4E89),
  Category.food => const Color(0xFFB45309),
  Category.travel => const Color(0xFF0F766E),
  Category.entertainment => const Color(0xFF6D28D9),
  Category.utility => const Color(0xFF0369A1),
  Category.personalCare => const Color(0xFFBE185D),
  Category.grocery => const Color(0xFF3F6212),
  Category.clothing => const Color(0xFF9A3412),
};

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.onTap,
  });

  final Transaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = categoryAccent(t.category);
    final purchase = t.type == TransactionType.purchase;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Material(
        color: scheme.surface,
        elevation: 2,
        shadowColor: accent.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              Container(width: 5, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          purchase
                              ? Icons.storefront_outlined
                              : Icons.person_outline,
                          color: accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.payeeName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${t.category.label} · ${formatBangkokDate(t.occurredAt)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (t.memo != null)
                              Text(
                                t.memo!,
                                key: const Key('tile-memo'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatThb(t.amountMinor),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: purchase
                              ? const Color(0xFF0F6E6B)
                              : const Color(0xFF6D28D9),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
