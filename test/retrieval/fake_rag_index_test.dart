import 'package:flutter_test/flutter_test.dart';

import '../support/fake_rag_index.dart';

void main() {
  test('identical text is a duplicate of the first source (engine semantics)', () async {
    final rag = FakeRagIndex();
    final a = await rag.addDocument('Purchase at Big Mart', name: 'x');
    final b = await rag.addDocument('Purchase at Big Mart', name: 'y');
    expect(a.isDuplicate, isFalse);
    expect(b.isDuplicate, isTrue);
    expect(b.chunkCount, 0);
    expect(b.sourceId, a.sourceId);
  });

  test('searches respect the allowlist and refuse an empty one', () async {
    final rag = FakeRagIndex();
    final camping = await rag.addDocument('Memo: tent for camping', name: 'a');
    final grocery = await rag.addDocument('Memo: rice and oil', name: 'b');
    final hits = await rag.searchHybrid('camping',
        topK: 10, sourceIds: [grocery.sourceId], vectorWeight: 0.5, bm25Weight: 0.5);
    expect(hits.every((h) => h.sourceId == grocery.sourceId), isTrue);
    expect(hits.single.bm25Rank, 0);
    final all = await rag.searchHybrid('camping',
        topK: 10, sourceIds: [camping.sourceId, grocery.sourceId], vectorWeight: 0.5, bm25Weight: 0.5);
    expect(all.first.sourceId, camping.sourceId);
    expect(all.first.bm25Rank, 1);
    expect(() => rag.searchHybrid('camping', topK: 10, sourceIds: const [], vectorWeight: 0.5, bm25Weight: 0.5),
        throwsArgumentError);
  });
}
