import 'package:flutter_rag/search/rules/text_spans.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('take() consumes matches; later patterns skip consumed text', () {
    final t = QueryText('Show 7-11 payments in 2025');
    expect(t.take(RegExp(r'7-11')).length, 1);
    expect(t.take(RegExp(r'\d+')).map((m) => m[0]), ['2025']);
    expect(t.isFree(5, 9), isFalse);
  });

  test('lower keeps indices and free segments are maximal', () {
    final t = QueryText('Find CAMPING gear');
    expect(t.lower, 'find camping gear');
    t.consume(5, 12);
    expect(t.freeSegments(), [(0, 5), (12, 17)]);
  });
}
