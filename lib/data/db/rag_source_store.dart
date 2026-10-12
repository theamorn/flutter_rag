import 'dart:math' as math;
import 'dart:typed_data';

import '../../retrieval/vector_codec.dart';
import '../../search/search_plan.dart';
import '../../search/search_sql.dart';
import 'app_database.dart';

class RagMapping {
  const RagMapping(this.txnId, this.sourceId, this.docText);

  final String txnId;
  final int sourceId;
  final String docText;
}

/// Our side of the index: txn id <-> engine source id, the exact document
/// text (the checkpoint for re-indexing), and the vector for the gate.
class RagSourceStore {
  RagSourceStore(this.db);

  final AppDatabase db;

  Future<Map<String, RagMapping>> all() async {
    final rows = await db
        .customSelect('SELECT txn_id, source_id, doc_text FROM rag_sources')
        .get();
    return {
      for (final r in rows)
        r.read<String>('txn_id'): RagMapping(
            r.read<String>('txn_id'), r.read<int>('source_id'), r.read<String>('doc_text')),
    };
  }

  Future<RagMapping?> get(String txnId) async {
    final rows = await db
        .customSelect('SELECT txn_id, source_id, doc_text FROM rag_sources WHERE txn_id = ?',
            variables: sqlVars([txnId]))
        .get();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return RagMapping(r.read<String>('txn_id'), r.read<int>('source_id'), r.read<String>('doc_text'));
  }

  Future<String?> txnIdForSource(int sourceId) async {
    final rows = await db
        .customSelect('SELECT txn_id FROM rag_sources WHERE source_id = ?',
            variables: sqlVars([sourceId]))
        .get();
    return rows.isEmpty ? null : rows.first.read<String>('txn_id');
  }

  Future<int> count() async => (await db
          .customSelect('SELECT COUNT(*) AS n FROM rag_sources')
          .getSingle())
      .read<int>('n');

  Future<void> upsert(String txnId, int sourceId, String docText, Float32List vector) =>
      db.customStatement(
        'INSERT OR REPLACE INTO rag_sources (txn_id, source_id, doc_text, vector) VALUES (?, ?, ?, ?)',
        [txnId, sourceId, docText, encodeVector(vector)],
      );

  Future<void> deleteTxn(String txnId) =>
      db.customStatement('DELETE FROM rag_sources WHERE txn_id = ?', [txnId]);

  Future<void> deleteSources(List<int> sourceIds) async {
    for (var i = 0; i < sourceIds.length; i += 500) {
      final chunk = sourceIds.sublist(i, math.min(i + 500, sourceIds.length));
      await db.customStatement(
          'DELETE FROM rag_sources WHERE source_id IN (${sqlMarks(chunk.length)})', chunk);
    }
  }

  /// Engine source ids of indexed transactions matching the plan's hard
  /// filters: the retrieval allowlist.
  Future<List<int>> sourceIdsFor(SearchPlan plan) async {
    final f = sqlFilterFor(plan, alias: 't');
    final rows = await db
        .customSelect(
          'SELECT r.source_id AS id FROM rag_sources r '
          'JOIN transactions t ON t.id = r.txn_id WHERE ${f.where}',
          variables: sqlVars(f.args),
        )
        .get();
    return [for (final r in rows) r.read<int>('id')];
  }

  Future<Map<int, String>> txnIdsForSources(List<int> sourceIds) async {
    if (sourceIds.isEmpty) return const {};
    final rows = await db
        .customSelect(
          'SELECT source_id, txn_id FROM rag_sources WHERE source_id IN (${sqlMarks(sourceIds.length)})',
          variables: sqlVars(sourceIds),
        )
        .get();
    return {for (final r in rows) r.read<int>('source_id'): r.read<String>('txn_id')};
  }

  Future<Map<String, Float32List>> vectorsFor(List<String> txnIds) async {
    if (txnIds.isEmpty) return const {};
    final rows = await db
        .customSelect(
          'SELECT txn_id, vector FROM rag_sources WHERE txn_id IN (${sqlMarks(txnIds.length)})',
          variables: sqlVars(txnIds),
        )
        .get();
    return {
      for (final r in rows) r.read<String>('txn_id'): decodeVector(r.read<Uint8List>('vector')),
    };
  }
}
