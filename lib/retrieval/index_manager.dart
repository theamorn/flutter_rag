import 'package:flutter/foundation.dart';

import '../core/transaction.dart';
import '../data/db/rag_source_store.dart';
import '../data/db/transaction_repository.dart';
import 'rag_index.dart';
import 'transaction_document.dart';

enum IndexPhase { idle, reconciling, indexing, ready, failed }

class IndexProgress {
  const IndexProgress(this.phase,
      {this.done = 0, this.total = 0, this.error, this.elapsed = Duration.zero});

  final IndexPhase phase;
  final int done;
  final int total;
  final String? error;

  /// Time spent in the current ensureIndexed() run.
  final Duration elapsed;
}

class IndexingError implements Exception {
  IndexingError(this.message);

  final String message;

  @override
  String toString() => 'IndexingError: $message';
}

/// Keeps the engine index in step with SQLite (spec §9 ingestion). The
/// rag_sources table is the checkpoint: a restart re-runs ensureIndexed()
/// and only touches rows that are missing or changed, indexing memo-bearing
/// transactions first before memo-less transactions.
class IndexManager {
  IndexManager({
    required this.repo,
    required this.store,
    required this.rag,
    this.batchSize = 50,
  });

  final TransactionRepository repo;
  final RagSourceStore store;
  final RagIndex rag;
  final int batchSize;

  final ValueNotifier<IndexProgress> progress =
      ValueNotifier(const IndexProgress(IndexPhase.idle));

  Future<void> _tail = Future.value();

  bool get isReady => progress.value.phase == IndexPhase.ready;

  /// Index work never overlaps: ingestion and memo refreshes queue up.
  Future<T> _serial<T>(Future<T> Function() body) {
    final result = _tail.then((_) => body());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> ensureIndexed() => _serial(_ensureIndexed);

  Future<void> refreshTransaction(String txnId) => _serial(() => _refresh(txnId));

  Future<void> _ensureIndexed() async {
    final watch = Stopwatch()..start();
    try {
      progress.value = const IndexProgress(IndexPhase.reconciling);
      await _reconcile();
      final mappings = await store.all();
      final rows = await repo.all();
      final unindexed = [
        for (final t in rows)
          if (mappings[t.id]?.docText != transactionDocument(t)) t,
      ];
      final pending = [
        for (final t in unindexed)
          if (t.memo != null) t,
        for (final t in unindexed)
          if (t.memo == null) t,
      ];
      final total = rows.length;
      var done = total - pending.length;
      progress.value = IndexProgress(IndexPhase.indexing,
          done: done, total: total, elapsed: watch.elapsed);
      for (var i = 0; i < pending.length; i++) {
        await _index(pending[i], mappings[pending[i].id]);
        done++;
        if ((i + 1) % batchSize == 0 || i == pending.length - 1) {
          progress.value = IndexProgress(IndexPhase.indexing,
              done: done, total: total, elapsed: watch.elapsed);
          await Future<void>.delayed(Duration.zero); // let the UI breathe
        }
      }
      progress.value = IndexProgress(IndexPhase.ready,
          done: total, total: total, elapsed: watch.elapsed);
    } catch (e) {
      final p = progress.value;
      progress.value = IndexProgress(IndexPhase.failed,
          done: p.done, total: p.total, error: '$e', elapsed: watch.elapsed);
      rethrow;
    }
  }

  /// Engine sources without a matching mapping are removed; mappings whose
  /// source the engine no longer has are deleted (and re-indexed later).
  Future<void> _reconcile() async {
    final mappings = await store.all();
    final nameBySource = {for (final m in mappings.values) m.sourceId: m.txnId};
    final live = <int>{};
    for (final s in await rag.listSources()) {
      if (nameBySource[s.sourceId] == s.name) {
        live.add(s.sourceId);
      } else {
        await rag.removeSource(s.sourceId);
      }
    }
    final stale = [for (final id in nameBySource.keys) if (!live.contains(id)) id];
    if (stale.isNotEmpty) await store.deleteSources(stale);
  }

  Future<void> _index(Transaction t, RagMapping? old) async {
    final doc = transactionDocument(t);
    if (old != null) {
      await rag.removeSource(old.sourceId);
      await store.deleteTxn(t.id);
    }
    final vector = await rag.embed(doc);
    final result = await rag.addDocument(doc, name: t.id);
    // spec D6: isDuplicate with 0 chunks = a real duplicate; with chunks =
    // the engine resumed an interrupted ingestion (fine).
    if (result.isDuplicate && result.chunkCount == 0) {
      throw IndexingError('Document for ${t.id} duplicates engine source '
          '${result.sourceId}; every document must be unique (check the Ref suffix).');
    }
    final owner = await store.txnIdForSource(result.sourceId);
    if (owner != null && owner != t.id) {
      throw IndexingError(
          'Engine source ${result.sourceId} already belongs to $owner (indexing ${t.id}).');
    }
    await store.upsert(t.id, result.sourceId, doc, vector);
  }

  Future<void> _refresh(String txnId) async {
    final t = await repo.getById(txnId);
    if (t == null) return;
    final old = await store.get(txnId);
    if (old?.docText == transactionDocument(t)) return;
    await _index(t, old);
  }
}
