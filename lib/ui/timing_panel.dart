import 'package:flutter/material.dart';

import '../perf/stage_timer.dart';
import '../perf/timing_log.dart';

/// Developer timing panel (spec §11.10): last search + p50/p95 per path.
class TimingPanel extends StatelessWidget {
  const TimingPanel({
    super.key,
    required this.log,
    required this.lastTimings,
    required this.resources,
  });

  final TimingLog log;
  final Map<Stage, Duration> lastTimings;
  final ResourceSnapshot? Function() resources;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: log,
    builder: (context, _) {
      final small = Theme.of(context).textTheme.bodySmall;
      final last = [
        for (final stage in Stage.values)
          if (lastTimings[stage] case final d?)
            '${stage.name} ${formatMs(d)} ms',
      ].join(' · ');
      return Material(
        elevation: 4,
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Text('Timings (${log.samples.length} searches)'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last search: $last', style: small),
            for (final (advanced, semantic, label) in kTimingPaths)
              if (log.stats(advanced: advanced, semantic: semantic) case final s
                  when s.isNotEmpty)
                Text(
                  '$label (n=${s[Stage.total]?.n ?? 0}): '
                  '${[for (final e in s.entries) '${e.key.name} p50 ${formatMs(e.value.p50)} / p95 ${formatMs(e.value.p95)} ms'].join('; ')}',
                  style: small,
                ),
            if (resources() case final r?) Text(r.describe(), style: small),
          ],
        ),
      );
    },
  );
}
