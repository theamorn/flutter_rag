import 'dart:typed_data';

import 'package:mobile_rag_engine/mobile_rag_engine.dart';

const String kMiniLmModelAsset = 'assets/models/minilm/model.onnx';
const String kMiniLmTokenizerAsset = 'assets/models/minilm/tokenizer.json';

class RagHit {
  const RagHit({
    required this.sourceId,
    required this.score,
    required this.vectorRank,
    required this.bm25Rank,
  });

  final int sourceId;

  /// Fused RRF score: a rank artefact, NOT a similarity. Never gate on it.
  final double score;

  /// 0 = not in the vector list.
  final int vectorRank;

  /// 0 = no keyword match.
  final int bm25Rank;
}

class RagAddResult {
  const RagAddResult({
    required this.sourceId,
    required this.isDuplicate,
    required this.chunkCount,
  });

  final int sourceId;
  final bool isDuplicate;
  final int chunkCount;
}

class RagSource {
  const RagSource({required this.sourceId, this.name});

  final int sourceId;
  final String? name;
}

/// What the app needs from the retrieval engine. MobileRag on the phone,
/// FakeRagIndex in host tests.
abstract interface class RagIndex {
  Future<RagAddResult> addDocument(String text, {required String name});

  Future<void> removeSource(int sourceId);

  Future<List<RagSource>> listSources();

  /// Hybrid search restricted to [sourceIds]. Must not be empty: the engine
  /// treats `[]` as "no filter" and would search the whole corpus.
  Future<List<RagHit>> searchHybrid(
    String query, {
    required int topK,
    required List<int> sourceIds,
    required double vectorWeight,
    required double bm25Weight,
  });

  /// The same MiniLM embedding the engine uses (384 floats).
  Future<Float32List> embed(String text);
}

class MobileRagIndex implements RagIndex {
  MobileRagIndex._();

  /// One engine database per fixture size (spec D3).
  static Future<MobileRagIndex> open({required int fixtureSize}) async {
    await MobileRag.initialize(
      tokenizerAsset: kMiniLmTokenizerAsset,
      modelAsset: kMiniLmModelAsset,
      databaseName: 'rag_$fixtureSize.sqlite',
      threadLevel: ThreadUseLevel.medium,
    );
    return MobileRagIndex._();
  }

  @override
  Future<RagAddResult> addDocument(String text, {required String name}) async {
    final r = await MobileRag.instance.addDocument(text, name: name);
    return RagAddResult(
        sourceId: r.sourceId, isDuplicate: r.isDuplicate, chunkCount: r.chunkCount);
  }

  @override
  Future<void> removeSource(int sourceId) => MobileRag.instance.removeSource(sourceId);

  @override
  Future<List<RagSource>> listSources() async => [
        for (final s in await MobileRag.instance.listSources())
          RagSource(sourceId: s.id, name: s.name),
      ];

  @override
  Future<List<RagHit>> searchHybrid(
    String query, {
    required int topK,
    required List<int> sourceIds,
    required double vectorWeight,
    required double bm25Weight,
  }) async {
    if (sourceIds.isEmpty) {
      throw ArgumentError('Empty sourceIds would search the whole corpus.');
    }
    final hits = await MobileRag.instance.searchHybrid(
      query,
      topK: topK,
      sourceIds: sourceIds,
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
    );
    return [
      for (final h in hits)
        RagHit(
          sourceId: h.sourceId,
          score: h.score,
          vectorRank: h.vectorRank,
          bm25Rank: h.bm25Rank,
        ),
    ];
  }

  @override
  Future<Float32List> embed(String text) => EmbeddingService.embed(text);
}
