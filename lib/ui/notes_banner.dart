import 'package:flutter/material.dart';

import '../search/search_plan.dart';

/// Interpretation notes, validation errors and engine notices under the chips.
class NotesBanner extends StatelessWidget {
  const NotesBanner({super.key, required this.notes, required this.errors, this.notice});

  final List<PlanNote> notes;
  final List<String> errors;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty && errors.isEmpty && notice == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    Widget line(IconData icon, String text, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: small?.copyWith(color: color))),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final e in errors) line(Icons.error_outline, e, color: theme.colorScheme.error),
        if (notice != null) line(Icons.info_outline, notice!),
        for (final n in notes)
          line(
            switch (n.kind) {
              PlanNoteKind.assumption => Icons.lightbulb_outline,
              PlanNoteKind.ambiguous => Icons.help_outline,
              PlanNoteKind.unused => Icons.remove_circle_outline,
            },
            n.text,
          ),
      ]),
    );
  }
}
