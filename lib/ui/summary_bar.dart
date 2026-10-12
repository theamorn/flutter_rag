import 'package:flutter/material.dart';

import '../results/result_summary.dart';

class SummaryBar extends StatelessWidget {
  const SummaryBar({
    super.key,
    required this.summary,
    this.busy = false,
    this.trailing,
  });

  final ResultSummary? summary;
  final bool busy;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (s != null)
          Container(
          margin: const EdgeInsets.fromLTRB(12, 2, 12, 2),
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE5F4F3),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x240F6E6B),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.countLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF0F6E6B),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              s.totalText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (s.isCandidateSet)
                            const Tooltip(
                              message: kCandidateSubtotalNote,
                              child: Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Color(0xFF0F6E6B),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        if (busy)
          const LinearProgressIndicator(minHeight: 2, color: Color(0xFF0F6E6B)),
      ],
    );
  }
}
