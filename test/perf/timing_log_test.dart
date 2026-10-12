import 'package:flutter_rag/perf/stage_timer.dart';
import 'package:flutter_rag/perf/timing_log.dart';
import 'package:flutter_test/flutter_test.dart';

Duration ms(int v) => Duration(milliseconds: v);

TimingSample sample(
  int total, {
  bool advanced = false,
  bool semantic = false,
}) => TimingSample(
  query: 'q',
  advanced: advanced,
  semantic: semantic,
  stages: {Stage.total: ms(total), Stage.sqlFilter: ms(total ~/ 4)},
);

void main() {
  test('nearest-rank percentiles', () {
    final values = [for (var i = 1; i <= 10; i++) ms(i)];
    expect(percentile(values, 50), ms(5));
    expect(percentile(values, 95), ms(10));
    expect(percentile([ms(7)], 95), ms(7));
    expect(() => percentile(const [], 50), throwsArgumentError);
  });

  test('stats are grouped by path', () {
    final log = TimingLog()
      ..add(sample(100))
      ..add(sample(200))
      ..add(sample(4000, advanced: true, semantic: true));
    final exact = log.stats(advanced: false, semantic: false);
    expect(exact[Stage.total]!.n, 2);
    expect(exact[Stage.total]!.p95, ms(200));
    expect(
      log.stats(advanced: true, semantic: true)[Stage.total]!.p50,
      ms(4000),
    );
    expect(log.stats(advanced: false, semantic: true), isEmpty);
  });

  test('markdown report has one table row per stage and path', () {
    final log = TimingLog()..add(sample(120));
    final md = log.toMarkdown();
    expect(md, contains('| Standard exact | total | 1 | 120 | 120 |'));
  });
}
