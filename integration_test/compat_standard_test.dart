import 'package:flutter/foundation.dart';
import 'package:flutter_rag/dev/compat_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // debugPrint is throttled and queued; the test can end before late lines
  // flush, and the engine's native logging makes that likely.
  debugPrint = debugPrintSynchronously;

  testWidgets('ML Kit, MobileRag and Drift work on this phone', (tester) async {
    final checks = await runStandardStackProbe();
    for (final c in checks) {
      debugPrint(c.toLine());
    }
    final failed = checks.where((c) => !c.passed).map((c) => c.toLine());
    expect(failed, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
