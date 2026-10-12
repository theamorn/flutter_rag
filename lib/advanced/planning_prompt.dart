import 'dart:convert';

import '../core/bangkok_time.dart';
import '../core/categories.dart';
import '../core/payees.dart';
import '../search/search_plan.dart';
import 'gemma_tool.dart';
import 'plan_args.dart';

String _days(DateRange range) =>
    '${formatBangkokIsoDate(range.start)} to '
    '${formatBangkokIsoDate(range.end.subtract(const Duration(milliseconds: 1)))}';

String buildPlanningSystemPrompt({
  required Iterable<String> shops,
  required Iterable<String> people,
}) {
  final now = toBangkokWallClock(kReferenceNow);
  return [
    "Turn the user's payment question into ONE search_transactions tool call. Always call the tool; never answer in prose.",
    'Today is ${formatBangkokIsoDate(kReferenceNow)}. Timezone Asia/Bangkok. Currency THB.',
    'Data covers 2023-10-01 to 2026-09-30. Every payment is outgoing.',
    'Purchases go to shops. Transfers go to people.',
    'Family means ${kFamilyGroup.join(', ')}: set family true.',
    'Known shops: ${shops.take(40).join(', ')}.',
    'Known people: ${people.join(', ')}.',
    'Categories:',
    for (final c in Category.values)
      '- ${c.dbValue}: ${kCategoryDefinitions[c]}',
    'Dates are Bangkok calendar days, inclusive. "last month" = ${_days(bangkokMonth(now.year, now.month - 1))}. '
        '"last year" = ${_days(bangkokYear(now.year - 1))}.',
    'Preserve EVERY requested constraint. A question with a date must include BOTH date_from '
        'and date_to, even when it also requests amount limits and a purpose. '
        'Worked example: "camping purchases under THB 3,000 excluding food last month" '
        'calls search_transactions with '
        '{"date_from":"2026-09-01","date_to":"2026-09-30","amount_max":3000,'
        '"amount_max_inclusive":false,"exclude_categories":["food"],'
        '"transaction_type":"purchase","semantic_query":"camping"}. '
        'Check the complete call against every constraint before submitting it.',
    '"under X" means amount_max X and amount_max_inclusive false; "at most X" means true. '
        '"over X" means amount_min X and amount_min_inclusive false; "at least X" means true.',
    '"excluding X" or "not X" goes in exclude_categories.',
    'semantic_query holds purpose words only; omit it for exact filters. '
        'Do not put dates, amounts, categories, shops or people in semantic_query.',
    'Include only constraints the question asks for.',
  ].join('\n');
}

String buildPlanningUserTurn(String query) => 'Question: $query';

String buildFollowUpUserTurn({
  required String followUp,
  required String? previousQuery,
  required SearchPlan current,
}) => [
  if (previousQuery != null && previousQuery.trim().isNotEmpty)
    'Previous question: $previousQuery',
  'Current filters (search_transactions arguments): ${jsonEncode(planToToolArgs(current))}',
  'Follow-up: $followUp',
  'Call search_transactions with ONLY the fields that change. To remove a filter, '
      'list it in "clear" (${kClearableFields.join(', ')}). Fields left out keep their values. '
      'Keep every unchanged constraint, including amount limits.',
].join('\n');
