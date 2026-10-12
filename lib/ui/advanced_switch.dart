import 'package:flutter/material.dart';

import '../advanced/advanced_controller.dart';

/// "Advanced reasoning" (default off). Turning it on loads Gemma, or asks
/// for setup when the model isn't downloaded. Turning it off frees memory.
class AdvancedSwitch extends StatelessWidget {
  const AdvancedSwitch({
    super.key,
    required this.controller,
    required this.onNeedsSetup,
  });

  final AdvancedController controller;
  final VoidCallback onNeedsSetup;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final theme = Theme.of(context);
      final statusColor = switch (c.toggle) {
        AdvancedToggle.on => theme.colorScheme.primary,
        AdvancedToggle.enabling => const Color(0xFFB45309),
        AdvancedToggle.off => theme.colorScheme.onSurfaceVariant,
      };
      return Card(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: SwitchListTile(
          dense: true,
          title: Text(
            'Advanced reasoning',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (c.toggle) {
                AdvancedToggle.enabling => 'Loading Gemma 4 E2B…',
                AdvancedToggle.on => 'Gemma 4 E2B ready',
                AdvancedToggle.off => 'Use the optional on-device model for complex questions and explanations.',
              }, style: TextStyle(color: statusColor)),
              if (c.error != null && c.toggle == AdvancedToggle.off)
                Text(
                  c.error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
            ],
          ),
          secondary: c.toggle == AdvancedToggle.enabling
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.psychology_outlined, color: statusColor),
          value: c.toggle != AdvancedToggle.off,
          onChanged: c.toggle == AdvancedToggle.enabling
              ? null
              : (on) async {
                  if (!on) {
                    await c.disable();
                  } else if (!await c.requestEnable()) {
                    onNeedsSetup();
                  }
                },
        ),
      );
    },
  );
}
