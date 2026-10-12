import 'dart:io';

import 'package:flutter/foundation.dart';

import 'stage_timer.dart';

/// Nearest-rank percentile: the smallest value with at least p% of values
/// at or below it.
Duration percentile(List<Duration> values, double p) {
  if (values.isEmpty) throw ArgumentError('no values');
  final sorted = [...values]..sort();
  final rank = (p / 100 * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}

class StageStats {
  const StageStats(this.n, this.p50, this.p95);

  final int n;
  final Duration p50;
  final Duration p95;
}

const List<(bool, bool, String)> kTimingPaths = [
  (false, false, 'Standard exact'),
  (false, true, 'Standard semantic'),
  (true, false, 'Advanced exact'),
  (true, true, 'Advanced semantic'),
];

String formatMs(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(0);

class TimingLog extends ChangeNotifier {
  final List<TimingSample> samples = [];

  void add(TimingSample sample) {
    samples.add(sample);
    notifyListeners();
  }

  void clear() {
    samples.clear();
    notifyListeners();
  }

  Map<Stage, StageStats> stats({
    required bool advanced,
    required bool semantic,
  }) {
    final group = samples.where(
      (s) => s.advanced == advanced && s.semantic == semantic,
    );
    final out = <Stage, StageStats>{};
    for (final stage in Stage.values) {
      final values = [
        for (final s in group)
          ?s.stages[stage],
      ];
      if (values.isNotEmpty) {
        out[stage] = StageStats(
          values.length,
          percentile(values, 50),
          percentile(values, 95),
        );
      }
    }
    return out;
  }

  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('| path | stage | n | p50 ms | p95 ms |')
      ..writeln('|---|---|---|---|---|');
    for (final (advanced, semantic, label) in kTimingPaths) {
      stats(advanced: advanced, semantic: semantic).forEach((stage, s) {
        b.writeln(
          '| $label | ${stage.name} | ${s.n} | ${formatMs(s.p50)} | ${formatMs(s.p95)} |',
        );
      });
    }
    return b.toString();
  }
}

/// Process memory and on-disk sizes at one moment.
class ResourceSnapshot {
  const ResourceSnapshot({required this.rssBytes, required this.fileBytes});

  final int rssBytes;
  final Map<String, int> fileBytes;

  static ResourceSnapshot capture(List<String> paths) => ResourceSnapshot(
    rssBytes: ProcessInfo.currentRss,
    fileBytes: {
      for (final p in paths)
        if (File(p).existsSync()) p.split('/').last: File(p).lengthSync(),
    },
  );

  String describe() {
    String mb(int b) =>
        '${(b / 1048576).toStringAsFixed(b < 10 * 1048576 ? 1 : 0)} MB';
    return [
      'RSS ${mb(rssBytes)}',
      for (final e in fileBytes.entries) '${e.key} ${mb(e.value)}',
    ].join(' · ');
  }
}
