import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/search/mlkit_entity_source.dart';
import 'package:flutter_rag/search/rules/rule_parser.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_rag/search/standard_interpreter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ML Kit + rules give the expected plans on the phone', (tester) async {
    // Exercise setup even on a retained model: Task 27 checks the iOS
    // extractor completion path instead of the broken manager callback.
    expect(await MlKitEntitySource.downloadModel(), isTrue);
    final source = MlKitEntitySource();
    final interpreter = StandardInterpreter(
      entities: source,
      parser: RuleParser(
        directory: PayeeDirectory(
          shops: const ['7-11', 'Sushiro', 'TermsGames', 'Uniqlo', 'Big Mart'],
          people: kFamilyGroup,
        ),
      ),
    );
    final cases = <String, SearchPlan>{
      'Show food payments under THB 300 last month': SearchPlan(
        dateRange: bangkokMonth(2026, 9),
        maxAmount: const AmountBound(30000, inclusive: false),
        includeCategories: const {Category.food},
      ),
      'Find things I bought for camping last month, under THB 3,000, excluding food.': SearchPlan(
        dateRange: bangkokMonth(2026, 9),
        maxAmount: const AmountBound(300000, inclusive: false),
        excludeCategories: const {Category.food},
        transactionType: TransactionType.purchase,
        semanticQuery: 'camping',
      ),
      'Show my 7-11 payments last month':
          SearchPlan(shopNames: const {'7-11'}, dateRange: bangkokMonth(2026, 9)),
    };
    for (final entry in cases.entries) {
      final sw = Stopwatch()..start();
      final plan = await interpreter.interpret(entry.key);
      debugPrint('STANDARD ${sw.elapsedMilliseconds} ms "${entry.key}" -> $plan');
      expect(plan, entry.value, reason: entry.key);
      // Plan equality ignores notes, so check the ML Kit call really ran.
      expect(plan.notes.where((n) => n.text.contains('rules only')), isEmpty,
          reason: 'ML Kit must not have fallen back: ${entry.key}');
    }
    await source.close();
  });
}
