import '../data/db/rag_source_store.dart';
import '../data/db/transaction_repository.dart';
import '../retrieval/rag_index.dart';
import '../retrieval/vector_codec.dart';
import '../search/plan_validator.dart';
import '../search/rules/rule_parser.dart';
import 'eval_queries.dart';

/// For each semantic query and no-match probe: run hybrid retrieval inside
/// the hard filters with NO gate, and record each top-10 hit's cosine and
/// keyword rank. Returns markdown for docs/calibration.md.
Future<String> runCalibration({
  required TransactionRepository repo,
  required RagSourceStore store,
  required RagIndex rag,
  required PlanValidator validator,
  required RuleParser parser,
  double vectorWeight = 0.5,
  double bm25Weight = 0.5,
}) async {
  final out = StringBuffer()
    ..writeln('| query | rank | txn | cosine | bm25Rank | label |')
    ..writeln('|---|---|---|---|---|---|');
  final positives = <double>[]; // cosine of relevant hits in the top 10
  final negativesTop = <double>[]; // best cosine per no-match probe
  final negativesTopKeyword = <double>[]; // best cosine among keyword hits

  Future<void> probe(String label, String text, Set<String> relevant) async {
    final plan = validator.validate(parser.parse(text)).plan;
    if (plan == null || !plan.hasSemanticIntent) return;
    final sourceIds = await store.sourceIdsFor(plan);
    if (sourceIds.isEmpty) return;
    final hits = await rag.searchHybrid(plan.semanticQuery!,
        topK: 200, sourceIds: sourceIds, vectorWeight: vectorWeight, bm25Weight: bm25Weight);
    final q = await rag.embed(plan.semanticQuery!);
    final byId = await store.txnIdsForSources([for (final h in hits.take(10)) h.sourceId]);
    final vectors = await store.vectorsFor(byId.values.toList());
    var best = -1.0;
    var bestKeyword = -1.0;
    for (final (i, h) in hits.take(10).indexed) {
      final id = byId[h.sourceId];
      if (id == null) continue;
      final cos = cosineSimilarity(q, vectors[id]!);
      final isRelevant = relevant.contains(id);
      if (isRelevant) positives.add(cos);
      if (cos > best) best = cos;
      if (h.bm25Rank > 0 && cos > bestKeyword) bestKeyword = cos;
      out.writeln('| $label | ${i + 1} | $id | ${cos.toStringAsFixed(3)} | ${h.bm25Rank} | '
          '${isRelevant ? 'relevant' : ''} |');
    }
    if (relevant.isEmpty) {
      negativesTop.add(best);
      if (bestKeyword >= 0) negativesTopKeyword.add(bestKeyword);
    }
  }

  for (final q in kEvalQueries.where((q) => q.kind == EvalKind.semantic)) {
    await probe(q.id, q.text, q.relevant);
  }
  for (final text in kNoMatchProbes) {
    await probe('none', text, const {});
  }

  double maxOf(List<double> xs) => xs.isEmpty ? double.nan : xs.reduce((a, b) => a > b ? a : b);
  double minOf(List<double> xs) => xs.isEmpty ? double.nan : xs.reduce((a, b) => a < b ? a : b);
  out
    ..writeln()
    ..writeln('- weights: vector $vectorWeight / bm25 $bm25Weight')
    ..writeln('- lowest relevant cosine (top 10): ${minOf(positives).toStringAsFixed(3)}')
    ..writeln('- highest no-match cosine: ${maxOf(negativesTop).toStringAsFixed(3)}')
    ..writeln('- highest no-match cosine among keyword hits: ${maxOf(negativesTopKeyword).toStringAsFixed(3)}');
  return out.toString();
}
