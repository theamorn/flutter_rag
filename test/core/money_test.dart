import 'package:flutter_rag/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats satang as THB with thousands separators', () {
    expect(formatThb(129900), 'THB 1,299.00');
    expect(formatThb(5), 'THB 0.05');
    expect(formatThb(300000000), 'THB 3,000,000.00');
  });

  test('parses baht text into satang', () {
    expect(parseBahtToMinor('3,000'), 300000);
    expect(parseBahtToMinor('1299.5'), 129950);
    expect(parseBahtToMinor('1,299.00'), 129900);
    expect(parseBahtToMinor('12,34'), isNull);
    expect(parseBahtToMinor('abc'), isNull);
  });
}
