import '../../core/bangkok_time.dart';
import '../search_plan.dart';
import 'rule_parser.dart';

const String kStandardFollowUpUnsupported =
    "Standard search can't apply that follow-up. Turn on Advanced reasoning "
    'for conversational follow-ups.';

/// Standard-mode follow-ups (spec §8): date shifts plus any filter phrase
/// the rule parser recognises, merged into the current plan.
class RuleRefiner {
  RuleRefiner(this.parser);

  final RuleParser parser;

  static final RegExp _backOneYear = RegExp(
      r'\b(?:go\s+back\s+(?:one|a|1)\s+year|(?:one|a|1)\s+year\s+(?:earlier|before|back)|the\s+year\s+before|previous\s+year)\b');
  static final RegExp _monthBefore = RegExp(r'\binclude\s+the\s+month\s+before\b');
  static final RegExp _monthAfter = RegExp(r'\binclude\s+the\s+month\s+after\b');
  static final RegExp _meaningDelta = RegExp(r'\b(?:about|for)\s+(.+)$');
  static const Set<String> _followUpMetaWords = {
    'more',
    'less',
    'fancier',
    'cheaper',
    'better',
    'worse',
    'other',
    'else',
    'instead',
    'only',
    'also',
    'too',
    'same',
    'different',
    'new',
    'old',
    'bigger',
    'smaller',
    'higher',
    'lower',
  };

  SearchPlan refine(SearchPlan current, String followUp) {
    final lower = followUp.toLowerCase();
    var plan = current;
    var changed = false;

    final range = current.dateRange;
    if (range != null) {
      var start = range.start;
      var end = range.end;
      if (_backOneYear.hasMatch(lower)) {
        start = _addMonths(start, -12);
        end = _addMonths(end, -12);
        changed = true;
      }
      if (_monthBefore.hasMatch(lower)) {
        start = _addMonths(start, -1);
        changed = true;
      }
      if (_monthAfter.hasMatch(lower)) {
        end = _addMonths(end, 1);
        changed = true;
      }
      plan = plan.copyWith(dateRange: DateRange(start, end));
    }

    // Remove the shift phrases so "previous year" is not also read as 2025.
    final rest = lower
        .replaceAll(_backOneYear, ' ')
        .replaceAll(_monthBefore, ' ')
        .replaceAll(_monthAfter, ' ');
    final delta = parser.parse(rest);
    final extraNotes = [
      for (final n in delta.notes)
        if (!n.text.startsWith('Searching by meaning')) n,
    ];

    if (delta.dateRange != null) {
      plan = plan.copyWith(dateRange: delta.dateRange);
      changed = true;
    }
    if (delta.minAmount != null) {
      plan = plan.copyWith(minAmount: delta.minAmount);
      changed = true;
    }
    if (delta.maxAmount != null) {
      plan = plan.copyWith(maxAmount: delta.maxAmount);
      changed = true;
    }
    if (delta.includeCategories.isNotEmpty) {
      plan = plan.copyWith(
        includeCategories: delta.includeCategories,
        excludeCategories: plan.excludeCategories.difference(delta.includeCategories),
      );
      changed = true;
    }
    if (delta.excludeCategories.isNotEmpty) {
      plan = plan.copyWith(
        excludeCategories: {...plan.excludeCategories, ...delta.excludeCategories},
        includeCategories: plan.includeCategories.difference(delta.excludeCategories),
      );
      changed = true;
    }
    if (delta.shopNames.isNotEmpty || delta.personNames.isNotEmpty) {
      plan = plan.copyWith(shopNames: delta.shopNames, personNames: delta.personNames);
      changed = true;
    }
    if (delta.transactionType != null && delta.transactionType != plan.transactionType) {
      plan = plan.copyWith(transactionType: delta.transactionType);
      changed = true;
    }
    if (delta.hasMemo != null) {
      plan = plan.copyWith(hasMemo: delta.hasMemo);
      changed = true;
    }
    // A new meaning when explicitly introduced ("... about X", "for X") or
    // when the follow-up is a bare topic replacement rather than filler/meta.
    final meaning = _meaningDelta.firstMatch(rest);
    if (meaning != null && delta.semanticQuery != null) {
      plan = plan.copyWith(semanticQuery: delta.semanticQuery);
      changed = true;
    } else if (!changed && extraNotes.isEmpty && delta.semanticQuery != null) {
      final words = delta.semanticQuery!.split(RegExp(r'\s+'));
      if (words.isNotEmpty && !words.any(_followUpMetaWords.contains)) {
        plan = plan.copyWith(semanticQuery: delta.semanticQuery);
        changed = true;
      }
    }

    if (!changed) {
      return current.copyWith(notes: const [
        PlanNote(PlanNoteKind.ambiguous, kStandardFollowUpUnsupported),
      ]);
    }
    return plan.copyWith(notes: [
      PlanNote(PlanNoteKind.assumption, 'Applied follow-up: "$followUp"'),
      ...extraNotes,
    ]);
  }

  static DateTime _addMonths(DateTime utc, int months) {
    final w = toBangkokWallClock(utc);
    return bangkokToUtc(w.year, w.month + months, w.day, w.hour, w.minute);
  }
}
