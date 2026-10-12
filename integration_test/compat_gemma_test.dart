import 'package:flutter/foundation.dart';
import 'package:flutter_rag/dev/gemma_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // debugPrint is throttled and can lose the last lines when the test ends.
  debugPrint = debugPrintSynchronously;

  testWidgets('Gemma 4 E2B downloads, plans with a forced tool call, cancels, closes',
      (tester) async {
    final checks = await runGemmaProbe();
    for (final c in checks) {
      debugPrint(c.toLine());
    }
    expect(checks.where((c) => !c.passed).map((c) => c.toLine()), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 90)));
}
