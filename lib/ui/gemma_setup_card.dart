import 'package:flutter/material.dart';

import '../advanced/advanced_controller.dart';
import '../advanced/gemma_model.dart';

class GemmaSetupCard extends StatefulWidget {
  const GemmaSetupCard({super.key, required this.controller});

  final AdvancedController controller;

  @override
  State<GemmaSetupCard> createState() => _GemmaSetupCardState();
}

class _GemmaSetupCardState extends State<GemmaSetupCard> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.install == ModelInstallState.unknown) {
      widget.controller.refreshInstallState();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final theme = Theme.of(context);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.psychology_outlined),
                  const SizedBox(width: 8),
                  Text('Gemma 4 E2B (optional)', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Download size: $kGemmaModelSizeLabel. Needs Wi-Fi and about 3 GB free. '
                'Keep this screen open while it downloads.',
              ),
              const SizedBox(height: 12),
              switch (c.install) {
                ModelInstallState.downloading => Column(
                  children: [
                    LinearProgressIndicator(value: c.downloadProgress / 100),
                    Row(
                      children: [
                        Text('${c.downloadProgress}%'),
                        const Spacer(),
                        TextButton(onPressed: c.cancelDownload, child: const Text('Cancel')),
                      ],
                    ),
                  ],
                ),
                ModelInstallState.installed =>
                  c.toggle == AdvancedToggle.enabling
                      ? const Row(
                          children: [
                            SizedBox.square(dimension: 24, child: CircularProgressIndicator()),
                            SizedBox(width: 12),
                            Text('Loading Gemma 4 E2B…'),
                          ],
                        )
                      : Wrap(
                          spacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(c.isOn ? 'Enabled' : 'Downloaded'),
                            if (c.isOn)
                              OutlinedButton(
                                onPressed: c.disable,
                                child: const Text('Turn off and free memory'),
                              )
                            else
                              FilledButton(onPressed: c.requestEnable, child: const Text('Enable')),
                          ],
                        ),
                ModelInstallState.unknown => const LinearProgressIndicator(),
                _ => FilledButton(
                  onPressed: c.downloadAndEnable,
                  child: Text(
                    c.install == ModelInstallState.failed
                        ? 'Retry download'
                        : 'Download and enable ($kGemmaModelSizeLabel)',
                  ),
                ),
              },
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(c.error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
            ],
          ),
        ),
      );
    },
  );
}
