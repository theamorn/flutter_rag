import 'package:integration_test/integration_test_driver.dart';

// flutter test only supports debug device builds. Use flutter drive --profile
// with this driver for the physical-phone probes, including the Gemma download.
Future<void> main() => integrationDriver(timeout: const Duration(minutes: 90));
