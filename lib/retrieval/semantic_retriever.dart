import '../data/db/rag_source_store.dart';
import '../data/db/transaction_repository.dart';
import '../perf/stage_timer.dart';
import '../search/search_plan.dart';
import 'rag_index.dart';
import 'vector_codec.dart';

class RetrievalConfig {
  const RetrievalConfig({
    this.maxCandidates = 200,
    this.vectorWeight = 0.5,
    this.bm25Weight = 0.5,
    this.fusionK = 60,
    this.minCosine = 0.40,
    this.minCosineWithKeyword = 0.25,
  });

  /// One gated list per query; the engine's allowlist ceiling is 200.
  final int maxCandidates;
  final double vectorWeight;
  final double bm25Weight;

  /// RRF constant for ordering the engine's hits: each hit scores
  /// `vectorWeight / (fusionK + vectorRank) + bm25Weight / (fusionK + bm25Rank)`.
  /// 60 reproduces the engine's own order (its k is fixed at 60). A small k
  /// lets the top of either list count: with 60, keyword rank 1 is worth no
  /// more than rank ~62 in both lists (docs/calibration.md, Task 25).
  final int fusionK;

  /// Keep a hit if cosine >= minCosine ...
  final double minCosine;

  /// ... or if it also matched by keyword and cosine >= this.
  final double minCosineWithKeyword;
}

/// Calibrated on CPH2499 (5,500 rows), 2026-10-04; fusionK and the keyword
/// floor re-measured in Task 25 (2026-10-05): see docs/calibration.md.
const RetrievalConfig kRetrievalConfig = RetrievalConfig(
  vectorWeight: 0.5,
  bm25Weight: 0.5,
  fusionK: 5,
  minCosine: 0.43,
  minCosineWithKeyword: 0.17,
);

class RankedIds {
  const RankedIds(this.ids, {this.gatedOut = 0, this.notIndexed = 0, this.eligible = 0});

  /// Transaction ids, best first, all inside the plan's hard filters.
  final List<String> ids;
  final int gatedOut;
  final int notIndexed;
  final int eligible;
}

/// Semantic retrieval inside the exact eligible set (spec §9 query path).
class SemanticRetriever {
  SemanticRetriever({
    required this.repo,
    required this.store,
    required this.rag,
    this.config = kRetrievalConfig,
  });

  final TransactionRepository repo;
  final RagSourceStore store;
  final RagIndex rag;
  final RetrievalConfig config;

  Future<RankedIds> retrieve(SearchPlan plan, StageTimer timer) async {
    final query = plan.semanticQuery!;
    // 1. Exact filters first. Empty -> stop: [] would mean "no filter".
    final eligible =
        await timer.time(Stage.sqlFilter, () => repo.summarize(plan.copyWith(limit: null)));
    if (eligible.count == 0) return const RankedIds([]);
    final sourceIds = await timer.time(Stage.sqlFilter, () => store.sourceIdsFor(plan));
    if (sourceIds.isEmpty) {
      return RankedIds(const [], notIndexed: eligible.count, eligible: eligible.count);
    }

    // 2. Hybrid ranking inside the allowlist (exact scan, up to 200).
    final hits = await timer.time(
      Stage.retrieval,
      () => rag.searchHybrid(
        query,
        topK: config.maxCandidates,
        sourceIds: sourceIds,
        vectorWeight: config.vectorWeight,
        bm25Weight: config.bm25Weight,
      ),
    );
    if (hits.isEmpty) {
      return RankedIds(const [],
          notIndexed: eligible.count - sourceIds.length, eligible: eligible.count);
    }

    // 3. Absolute relevance gate: cosine(query, stored document vector),
    // applied in the app's fused order (see RetrievalConfig.fusionK).
    final queryVector = await timer.time(Stage.queryEmbedding, () => rag.embed(query));
    return timer.time(Stage.gate, () async {
      final txnBySource = await store.txnIdsForSources([for (final h in hits) h.sourceId]);
      final vectors = await store.vectorsFor(txnBySource.values.toList());
      final ranked = <String>[];
      final seen = <String>{};
      var gated = 0;
      for (final h in _fused(hits)) {
        final id = txnBySource[h.sourceId];
        if (id == null || !seen.add(id)) continue;
        final v = vectors[id];
        if (v == null) continue;
        final cos = cosineSimilarity(queryVector, v);
        final keep = cos >= config.minCosine ||
            (h.bm25Rank > 0 && cos >= config.minCosineWithKeyword);
        if (keep) {
          ranked.add(id);
        } else {
          gated++;
        }
      }
      final limit = plan.limit;
      return RankedIds(
        limit == null ? ranked : ranked.take(limit).toList(),
        gatedOut: gated,
        notIndexed: eligible.count - sourceIds.length,
        eligible: eligible.count,
      );
    });
  }

  /// Reciprocal rank fusion of the engine's vector and keyword ranks with
  /// [RetrievalConfig.fusionK]; equal scores keep the engine's order.
  List<RagHit> _fused(List<RagHit> hits) {
    double part(double weight, int rank) => rank > 0 ? weight / (config.fusionK + rank) : 0;
    final scored = [
      for (final (i, h) in hits.indexed)
        (i, h, part(config.vectorWeight, h.vectorRank) + part(config.bm25Weight, h.bm25Rank)),
    ]..sort((a, b) {
        final c = b.$3.compareTo(a.$3);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return [for (final (_, h, _) in scored) h];
  }
}
