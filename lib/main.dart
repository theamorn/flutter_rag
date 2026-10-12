import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'app_services.dart';
import 'dev/bench_runner.dart';
import 'dev/calibration_runner.dart';
import 'dev/compat_probe.dart';
import 'dev/eval_runner.dart';
import 'dev/gemma_probe.dart';
import 'retrieval/index_manager.dart';
import 'search/plan_validator.dart';
import 'search/rules/rule_parser.dart';

Future<void> main() async {
  final coldStart = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('COMPAT_PROBE')) {
    unawaited(_runProbe('compat_probe.txt', runStandardStackProbe));
  }
  if (const bool.fromEnvironment('GEMMA_PROBE')) {
    unawaited(
      _runProbe('gemma_probe.txt', runGemmaProbe),
    ); // prints GEMMA_PROBE lines
  }
  final services = await AppServices.boot();
  if (const bool.fromEnvironment('RUN_CALIBRATION')) {
    unawaited(() async {
      await services.index!.ensureIndexed();
      for (final (v, b) in const [(0.5, 0.5), (0.7, 0.3), (0.2, 0.8)]) {
        final report = await runCalibration(
          repo: services.repo,
          store: services.store,
          rag: services.ragIndex!,
          validator: PlanValidator(services.directory),
          parser: RuleParser(directory: services.directory),
          vectorWeight: v,
          bm25Weight: b,
        );
        debugPrint('CALIBRATION_BEGIN\n$report\nCALIBRATION_END');
      }
    }());
  }
  if (const bool.fromEnvironment('RUN_EVAL')) {
    unawaited(() async {
      var report = '';
      try {
        await services.index?.ensureIndexed();
        report = await runEvaluation(services, advanced: false);
        if (const bool.fromEnvironment('EVAL_ADVANCED')) {
          final advanced = services.advanced;
          if (advanced != null &&
              await advanced.requestEnable() &&
              advanced.isOn) {
            try {
              report =
                  '$report\n\n${await runEvaluation(services, advanced: true)}';
            } finally {
              await advanced.disable();
            }
          } else {
            report =
                '$report\n\nAdvanced evaluation skipped: Gemma is not installed or '
                'did not load (${advanced?.error ?? 'no error'}).';
          }
        }
      } catch (e, st) {
        // Keep whatever finished, e.g. the standard section.
        report = '$report\n\nEVAL FAILED: $e\n$st';
      }
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/eval_report.md').writeAsString(report);
      debugPrint('EVAL_REPORT_BEGIN\n$report\nEVAL_REPORT_END');
    }());
  }
  unawaited(services.search.browse());
  runApp(TransactionSearchApp(services: services));
  final launchLines = <String>[];
  final benchmarkRun = const bool.fromEnvironment('RUN_BENCH');
  Future<void> saveLaunchLines() async {
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/bench_launch_${services.fixtureSize}.txt')
        .writeAsString(launchLines.join('\n'));
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final line =
        'COLD_START first frame after ${coldStart.elapsedMilliseconds} ms';
    debugPrint(line);
    launchLines.add(line);
    if (benchmarkRun) unawaited(saveLaunchLines());
  });
  var indexReadyLogged = false;
  void logIndexReady() {
    final p = services.index?.progress.value;
    if (p?.phase == IndexPhase.ready && !indexReadyLogged) {
      indexReadyLogged = true;
      final line =
          'INDEX_READY ${p!.total} docs in ${p.elapsed.inMilliseconds} ms this launch';
      debugPrint(line);
      launchLines.add(line);
      if (benchmarkRun) unawaited(saveLaunchLines());
    }
  }

  services.index?.progress.addListener(logIndexReady);
  logIndexReady(); // Boot may already have finished reuse before listener registration.
  if (benchmarkRun) {
    unawaited(() async {
      String report;
      try {
        if (!(services.index?.isReady ?? true)) {
          await services.index?.ensureIndexed();
        }
        report = await runBenchmark(
          services,
          advanced: const bool.fromEnvironment('BENCH_ADVANCED'),
        );
      } catch (e, st) {
        report = 'BENCH FAILED: $e\n$st';
      }
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/bench_report_${services.fixtureSize}.md')
          .writeAsString(report);
      debugPrint('BENCH_REPORT_BEGIN\n$report\nBENCH_REPORT_END');
    }());
  }
}

/// Release builds on the reference phone print nothing to logcat, so a probe
/// result is also written to a file that `adb pull` can read.
Future<void> _runProbe(
  String fileName,
  Future<List<ProbeCheck>> Function() run,
) async {
  final checks = await run();
  final dir = await getExternalStorageDirectory();
  if (dir == null) return;
  await File('${dir.path}/$fileName')
      .writeAsString(checks.map((c) => c.toLine()).join('\n'));
}
