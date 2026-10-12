import 'dart:typed_data';

import 'package:flutter_rag/retrieval/vector_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('float32 vectors round-trip through bytes', () {
    final v = Float32List.fromList([0.25, -1.5, 3.0, 0]);
    final bytes = encodeVector(v);
    expect(bytes.length, 16);
    expect(decodeVector(bytes), v);
  });

  test('cosine similarity', () {
    final a = Float32List.fromList([1, 0, 0]);
    expect(cosineSimilarity(a, Float32List.fromList([2, 0, 0])), closeTo(1, 1e-6));
    expect(cosineSimilarity(a, Float32List.fromList([0, 1, 0])), closeTo(0, 1e-6));
    expect(cosineSimilarity(a, Float32List(3)), 0);
    expect(() => cosineSimilarity(a, Float32List(4)), throwsArgumentError);
  });
}
