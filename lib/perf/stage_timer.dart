/// Timing stages (spec §12). `total` = submit to first rows in the list.
enum Stage {
  modelLoad,
  interpret,
  sqlFilter,
  queryEmbedding,
  retrieval,
  gate,
  rowFetch,
  answer,
  total,
}

/// Collects per-stage durations for one search.
class StageTimer {
  final Map<Stage, Duration> _durations = {};

  Map<Stage, Duration> get durations => Map.unmodifiable(_durations);

  Future<T> time<T>(Stage stage, Future<T> Function() body) async {
    final watch = Stopwatch()..start();
    try {
      return await body();
    } finally {
      add(stage, watch.elapsed);
    }
  }

  void add(Stage stage, Duration duration) =>
      _durations[stage] = (_durations[stage] ?? Duration.zero) + duration;
}

/// One finished search, for the timing panel (Task 24).
class TimingSample {
  const TimingSample({
    required this.query,
    required this.advanced,
    required this.semantic,
    required this.stages,
  });

  final String query;
  final bool advanced;
  final bool semantic;
  final Map<Stage, Duration> stages;
}
