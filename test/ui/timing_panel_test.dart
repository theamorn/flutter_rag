import 'package:flutter/material.dart';
import 'package:flutter_rag/perf/stage_timer.dart';
import 'package:flutter_rag/perf/timing_log.dart';
import 'package:flutter_rag/ui/timing_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the last search and per-path percentiles', (tester) async {
    final log = TimingLog()
      ..add(
        const TimingSample(
          query: 'q',
          advanced: false,
          semantic: false,
          stages: {Stage.total: Duration(milliseconds: 42)},
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimingPanel(
            log: log,
            lastTimings: const {Stage.total: Duration(milliseconds: 42)},
            resources: () => const ResourceSnapshot(
              rssBytes: 300 * 1048576,
              fileBytes: {'txn.sqlite': 2097152},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('total 42 ms'), findsOneWidget);
    expect(
      find.textContaining('Standard exact (n=1): total p50 42 / p95 42 ms'),
      findsOneWidget,
    );
    expect(find.textContaining('RSS 300 MB'), findsOneWidget);
  });
}
