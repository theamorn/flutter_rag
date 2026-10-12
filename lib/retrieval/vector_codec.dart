import 'dart:math' as math;
import 'dart:typed_data';

double cosineSimilarity(Float32List a, Float32List b) {
  if (a.length != b.length) {
    throw ArgumentError('dimension mismatch: ${a.length} vs ${b.length}');
  }
  var dot = 0.0;
  var na = 0.0;
  var nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

/// Little-endian float32 bytes (SQLite BLOB).
Uint8List encodeVector(Float32List v) {
  final bytes = ByteData(v.length * 4);
  for (var i = 0; i < v.length; i++) {
    bytes.setFloat32(i * 4, v[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

Float32List decodeVector(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return Float32List.fromList([
    for (var i = 0; i < bytes.length ~/ 4; i++) data.getFloat32(i * 4, Endian.little),
  ]);
}
