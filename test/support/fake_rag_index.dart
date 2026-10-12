import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_rag/retrieval/rag_index.dart';
import 'package:flutter_rag/retrieval/vector_codec.dart';

/// Deterministic stand-in for MobileRag in host tests:
/// - "embedding": hashed bag of content words, 1,024 dims;
/// - keyword rank: shared content words (0 = no keyword match);
/// - RRF fusion with k = 60 and the engine's candidate count;
/// - identical text returns the existing source with isDuplicate (engine).
class FakeRagIndex implements RagIndex {
  final Map<int, (String, String)> sources = {}; // id -> (name, text)
  final Map<String, int> _byText = {};
  int _nextId = 1;
  int embedCalls = 0;
  final List<List<int>> searches = [];

  /// Next add for these names answers "duplicate" (isDuplicate, 0 chunks).
  final Set<String> forceDuplicate = {};

  /// Next add for these names answers "resumed" (isDuplicate, 1 chunk).
  final Set<String> forceResume = {};

  @override
  Future<RagAddResult> addDocument(String text, {required String name}) async {
    if (forceDuplicate.remove(name)) {
      return RagAddResult(sourceId: sources.keys.first, isDuplicate: true, chunkCount: 0);
    }
    final existing = _byText[text];
    if (existing != null) {
      return RagAddResult(sourceId: existing, isDuplicate: true, chunkCount: 0);
    }
    final id = _nextId++;
    sources[id] = (name, text);
    _byText[text] = id;
    return RagAddResult(sourceId: id, isDuplicate: forceResume.remove(name), chunkCount: 1);
  }

  @override
  Future<void> removeSource(int sourceId) async {
    final s = sources.remove(sourceId);
    if (s != null) _byText.remove(s.$2);
  }

  @override
  Future<List<RagSource>> listSources() async =>
      [for (final e in sources.entries) RagSource(sourceId: e.key, name: e.value.$1)];

  @override
  Future<Float32List> embed(String text) async {
    embedCalls++;
    return fakeEmbedding(text);
  }

  @override
  Future<List<RagHit>> searchHybrid(
    String query, {
    required int topK,
    required List<int> sourceIds,
    required double vectorWeight,
    required double bm25Weight,
  }) async {
    if (sourceIds.isEmpty) {
      throw ArgumentError('empty sourceIds would search the whole corpus');
    }
    searches.add(List.of(sourceIds));
    final q = fakeEmbedding(query);
    final qWords = contentWords(query);
    final allowed = sourceIds.where(sources.containsKey).toList();
    final cos = {for (final id in allowed) id: cosineSimilarity(q, fakeEmbedding(sources[id]!.$2))};
    final overlap = {
      for (final id in allowed) id: contentWords(sources[id]!.$2).intersection(qWords).length,
    };
    int byScore(Map<int, num> m, int a, int b) {
      final c = m[b]!.compareTo(m[a]!);
      return c != 0 ? c : a.compareTo(b);
    }

    final candidates = (topK * 10).clamp(50, 200);
    final byVector = [...allowed]..sort((a, b) => byScore(cos, a, b));
    final byKeyword = allowed.where((id) => overlap[id]! > 0).toList()
      ..sort((a, b) => byScore(overlap, a, b));
    final vRank = {
      for (var i = 0; i < math.min(candidates, byVector.length); i++) byVector[i]: i + 1,
    };
    final kRank = {
      for (var i = 0; i < math.min(candidates, byKeyword.length); i++) byKeyword[i]: i + 1,
    };
    double rrf(int? rank) => rank == null ? 0 : 1 / (60 + rank);
    final hits = [
      for (final id in {...vRank.keys, ...kRank.keys})
        RagHit(
          sourceId: id,
          score: vectorWeight * rrf(vRank[id]) + bm25Weight * rrf(kRank[id]),
          vectorRank: vRank[id] ?? 0,
          bm25Rank: kRank[id] ?? 0,
        ),
    ]..sort((a, b) {
        final c = b.score.compareTo(a.score);
        return c != 0 ? c : a.sourceId.compareTo(b.sourceId);
      });
    return hits.take(topK).toList();
  }
}

const Set<String> _fakeStop = {
  'the', 'and', 'for', 'our', 'with', 'memo', 'purchase', 'transfer',
  'category', 'description', 'date', 'amount', 'thb', 'ref', 'txn', 'card',
  'payment', 'promptpay', 'bank', 'pos', 'jan', 'feb', 'mar', 'apr', 'may',
  'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
};

Set<String> contentWords(String text) => RegExp(r'[a-z]+')
    .allMatches(text.toLowerCase())
    .map((m) => m[0]!)
    .where((w) => w.length > 2 && !_fakeStop.contains(w))
    .toSet();

/// Bag of content words hashed (FNV-1a) into 1,024 dims.
Float32List fakeEmbedding(String text) {
  final v = Float32List(1024);
  for (final w in contentWords(text)) {
    var h = 0x811c9dc5;
    for (final c in w.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    v[h % 1024] += 1;
  }
  return v;
}
