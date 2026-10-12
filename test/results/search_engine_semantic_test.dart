import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/data/db/rag_source_store.dart';
import 'package:flutter_rag/data/db/seed.dart';
import 'package:flutter_rag/data/db/transaction_repository.dart';
import 'package:flutter_rag/perf/stage_timer.dart';
import 'package:flutter_rag/results/result_source.dart';
import 'package:flutter_rag/results/search_engine.dart';
import 'package:flutter_rag/retrieval/index_manager.dart';
import 'package:flutter_rag/retrieval/semantic_retriever.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_rag_index.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('semantic plans page a ranked candidate list with a subtotal', () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);
    await seedIfEmpty(db, repo, 300);
    final store = RagSourceStore(db);
    final rag = FakeRagIndex();
    await IndexManager(repo: repo, store: store, rag: rag).ensureIndexed();
    final engine = SearchEngine(
      repo: repo,
      retriever: SemanticRetriever(
        repo: repo, store: store, rag: rag,
        config: const RetrievalConfig(minCosine: 0.2, minCosineWithKeyword: 0.05),
      ),
    );
    final outcome = await engine.run(
        const SearchPlan(semanticQuery: 'housewarming', sort: SortOrder.relevance), StageTimer());
    expect(outcome.source, isA<RankedResultSource>());
    expect(outcome.summary.isCandidateSet, isTrue);
    final page = await outcome.source.fetch(0, 100);
    expect(page.rows.first.id, 'txn_a29');
    expect(outcome.summary.totalMinor, page.rows.fold<int>(0, (s, t) => s + t.amountMinor));
    await db.close();
  });
}
