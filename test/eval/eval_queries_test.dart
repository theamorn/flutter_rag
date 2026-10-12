import 'package:flutter_rag/data/fixture/authored.dart';
import 'package:flutter_rag/dev/eval_queries.dart';
import 'package:flutter_rag/search/plan_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('32 queries with unique ids', () {
    expect(kEvalQueries.length, 32);
    expect(kEvalQueries.map((q) => q.id).toSet().length, 32);
  });

  test('every labelled id is an authored row that satisfies the hard filters', () {
    final byId = {for (final t in kAuthoredTransactions) t.id: t};
    for (final q in kEvalQueries.where((q) => q.expected != null)) {
      for (final id in {...q.relevant, ...q.acceptable}) {
        final t = byId[id];
        expect(t, isNotNull, reason: '${q.id}: $id is not authored');
        expect(planMatches(q.expected!, t!), isTrue,
            reason: '${q.id}: $id cannot pass its own hard filters');
      }
    }
  });

  test('semantic queries have labels; no-match queries have none', () {
    for (final q in kEvalQueries) {
      if (q.kind == EvalKind.semantic) expect(q.relevant, isNotEmpty, reason: q.id);
      if (q.kind == EvalKind.noMatch) expect(q.relevant, isEmpty, reason: q.id);
    }
  });
}
