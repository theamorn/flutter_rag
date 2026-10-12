import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/app_services.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/retrieval/semantic_retriever.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_rag_index.dart';

// Fake embeddings score differently from MiniLM (see semantic_retriever_test).
const _fakeConfig = RetrievalConfig(minCosine: 0.2, minCosineWithKeyword: 0.05);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('without a retrieval engine the app is exact-only', () async {
    final services = await AppServices.open(AppDatabase.memory(), 300);
    expect(services.index, isNull);
    expect(services.ragIndex, isNull);
    await services.dispose();
  });

  test('with an engine, a meaning query is indexed, retrieved and ranked', () async {
    final services = await AppServices.open(AppDatabase.memory(), 300,
        rag: FakeRagIndex(), retrievalConfig: _fakeConfig);
    await services.index!.ensureIndexed();
    expect(services.index!.isReady, isTrue);
    await services.search.submit(
        'Find things I bought for camping last month, under THB 3,000, excluding food.');
    expect(services.search.plan.semanticQuery, 'camping');
    expect(services.search.summary!.isCandidateSet, isTrue);
    expect(services.search.pager.items.map((t) => t.id),
        containsAll(['txn_a01', 'txn_a02', 'txn_a03']));
    await services.dispose();
  });

  test('saving a memo refreshes that transaction in the index', () async {
    final services = await AppServices.open(AppDatabase.memory(), 300,
        rag: FakeRagIndex(), retrievalConfig: _fakeConfig);
    await services.index!.ensureIndexed();
    await services.search.updateMemo('txn_a29', 'Snacks for the office');
    expect((await services.store.get('txn_a29'))!.docText,
        startsWith('Memo: Snacks for the office.'));
    await services.dispose();
  });
}
