import 'package:flutter_rag/perf/stage_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('time() records a stage and add() accumulates', () async {
    final t = StageTimer();
    final v = await t.time(Stage.sqlFilter, () async => 42);
    expect(v, 42);
    expect(t.durations.containsKey(Stage.sqlFilter), isTrue);
    t.add(Stage.retrieval, const Duration(milliseconds: 5));
    t.add(Stage.retrieval, const Duration(milliseconds: 7));
    expect(t.durations[Stage.retrieval], const Duration(milliseconds: 12));
  });

  test('time() records even when the body throws', () async {
    final t = StageTimer();
    await expectLater(t.time(Stage.gate, () async => throw StateError('x')), throwsStateError);
    expect(t.durations.containsKey(Stage.gate), isTrue);
  });
}
