import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/data/fixture/fixture_generator.dart';
import 'package:flutter_rag/dev/eval_queries.dart';
import 'package:flutter_rag/search/rules/rule_parser.dart';
import 'package:flutter_rag/search/rules/rule_refiner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final full = buildFixture(5500);
  final parser = RuleParser(
    directory: PayeeDirectory(
      shops: full.map((t) => t.shopName).whereType<String>().toSet(),
      people: full.map((t) => t.personName).whereType<String>().toSet(),
    ),
  );

  for (final q in kEvalQueries.where((q) => q.expected != null)) {
    test('${q.id} standard plan: ${q.text}', () {
      final plan = q.kind == EvalKind.followUp
          ? RuleRefiner(parser).refine(parser.parse(evalQuery(q.followUpOf!).text), q.text)
          : parser.parse(q.text);
      expect(plan, q.expected);
      for (final kind in q.expectedNoteKinds) {
        expect(plan.notes.map((n) => n.kind), contains(kind));
      }
    });
  }
}
