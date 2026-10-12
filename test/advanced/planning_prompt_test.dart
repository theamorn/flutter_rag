import 'package:flutter_rag/advanced/planning_prompt.dart';
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'system prompt carries the reference date, worked examples and categories',
    () {
      final p = buildPlanningSystemPrompt(
        shops: const ['7-11', 'Sushiro'],
        people: const ['Mom'],
      );
      expect(p, contains('Today is 2026-10-03'));
      expect(p, contains('"last month" = 2026-09-01 to 2026-09-30'));
      expect(p, contains('"last year" = 2025-01-01 to 2025-12-31'));
      for (final c in Category.values) {
        expect(p, contains('- ${c.dbValue}: '));
      }
      expect(p, contains('Mom, Dad, Kids, Amorn'));
      expect(p, contains('Known shops: 7-11, Sushiro'));
    },
  );

  test('follow-up turn shows current filters as tool arguments and asks for changes only', () {
    final t = buildFollowUpUserTurn(
      followUp: 'go back one year',
      previousQuery: 'camping last month',
      current: SearchPlan(
        dateRange: bangkokMonth(2026, 9),
        semanticQuery: 'camping',
      ),
    );
    expect(t, contains('"date_from":"2026-09-01"'));
    expect(t, contains('"semantic_query":"camping"'));
    expect(t, contains('ONLY the fields that change'));
  });
  test('worked complex call includes dates and amount together as tool JSON', () {
    final prompt = buildPlanningSystemPrompt(shops: [], people: []);
    expect(prompt, contains('"date_from":"2026-09-01","date_to":"2026-09-30","amount_max":3000'));
  });


  test('a follow-up without a previous question omits that line', () {
    final t = buildFollowUpUserTurn(
      followUp: 'last year',
      previousQuery: null,
      current: SearchPlan.empty,
    );
    expect(t, isNot(contains('Previous question')));
    expect(t, contains('Follow-up: last year'));
  });
}
