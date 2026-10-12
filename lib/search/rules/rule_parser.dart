import '../../core/bangkok_time.dart';
import '../../core/categories.dart';
import '../../core/payees.dart';
import '../../core/transaction.dart';
import '../entities.dart';
import '../search_plan.dart';
import 'amount_rules.dart';
import 'date_rules.dart';
import 'text_spans.dart';

/// Standard-mode interpretation (spec §8): deterministic rules, applied in a
/// fixed order, each consuming the text it used. What is left is the meaning.
class RuleParser {
  RuleParser({required this.directory, DateTime? now}) : _dates = DateRules(now: now);

  final PayeeDirectory directory;
  final DateRules _dates;
  static const AmountRules _amounts = AmountRules();

  SearchPlan parse(String query, {List<ExtractedEntity> entities = const []}) {
    final text = QueryText(query);
    final notes = <PlanNote>[];

    // 1. Payees first, so "7-11" is never read as a date.
    final shops = <String>{};
    final people = <String>{};
    for (final alias in directory.phrases) {
      if (text.take(_phrase(alias.phrase)).isEmpty) continue;
      (alias.kind == PayeeKind.shop ? shops : people).add(alias.canonical);
    }
    final family = text.take(_family).isNotEmpty;
    if (family) people.addAll(kFamilyGroup);

    // 2. Memo presence.
    var wantsMemo = false;
    var wantsNoMemo = false;
    for (final r in _noMemo) {
      if (text.take(r).isNotEmpty) wantsNoMemo = true;
    }
    for (final r in _withMemo) {
      if (text.take(r).isNotEmpty) wantsMemo = true;
    }
    bool? hasMemo;
    if (wantsMemo && wantsNoMemo) {
      notes.add(const PlanNote(PlanNoteKind.ambiguous,
          'Asked for rows with and without memos; the memo filter is not applied.'));
    } else if (wantsMemo || wantsNoMemo) {
      hasMemo = wantsMemo;
    }

    // 3. Sort and limit.
    var sort = SortOrder.newest;
    int? limit;
    for (final m in text.take(_topN)) {
      limit = int.parse(m[1]!);
      sort = SortOrder.amountDesc;
    }
    for (final m in text.take(_nSorted)) {
      limit = int.parse(m[1]!);
      sort = _sortFor(m[2]!);
    }
    for (final m in text.take(_sortWords)) {
      sort = _sortFor(m[1]!);
    }

    // 4. Amounts with an operator.
    final amounts = _amounts.apply(text);
    notes.addAll(amounts.notes);

    // 5. Dates. Dart rules own dates.
    final dates = _dates.apply(text);
    notes.addAll(dates.notes);
    DateRange? range;
    for (final d in dates.matches) {
      if (range == null) {
        range = d.range;
      } else {
        notes.add(PlanNote(PlanNoteKind.ambiguous, 'Used the first date only; ignored "${d.text}".'));
      }
    }

    // 6. Money with a currency but no operator: noted, never filtered.
    notes.addAll(_amounts.flagBareAmounts(text));

    // 7. Categories: exclusions first, then plain mentions.
    final include = <Category>{};
    final exclude = <Category>{};
    for (final m in text.take(_negatedCategories)) {
      for (final a in _categoryWord.allMatches(m[1]!)) {
        exclude.add(_categoryAliases[_normalise(a[0]!)]!);
      }
    }
    for (final m in text.take(_categoryWord)) {
      include.add(_categoryAliases[_normalise(m[0]!)]!);
    }

    // 8. Transaction type.
    final saysTransfer = text.take(_transferWords).isNotEmpty;
    final saysPurchase = text.take(_purchaseWords).isNotEmpty;
    TransactionType? type;
    if (saysTransfer && saysPurchase) {
      notes.add(const PlanNote(PlanNoteKind.ambiguous,
          'Asked for both purchases and transfers; showing both.'));
    } else if (saysTransfer || (family && !saysPurchase)) {
      type = TransactionType.transfer;
    } else if (saysPurchase) {
      type = TransactionType.purchase;
    }

    // 9. ML Kit entities on text no rule claimed.
    for (final e in entities) {
      if (e.end > query.length || !text.isFree(e.start, e.end)) continue;
      text.consume(e.start, e.end);
      switch (e) {
        case ExtractedDate date:
          if (range == null) {
            final r = date.toRange();
            range = r;
            notes.add(PlanNote(PlanNoteKind.assumption, 'Read "${date.text}" as ${formatDateRange(r)}.'));
          } else {
            notes.add(PlanNote(PlanNoteKind.ambiguous, 'Ignored the extra date "${date.text}".'));
          }
        case ExtractedMoney money:
          notes.add(PlanNote(
            PlanNoteKind.ambiguous,
            money.isThb
                ? 'Unclear how to use "${money.text}": say under, over or exactly.'
                : 'Only THB amounts are supported; ignored "${money.text}".',
          ));
      }
    }

    // 10. Whatever is left is the meaning to search for.
    final semantic = _remainder(text);
    if (semantic != null) {
      notes.add(PlanNote(PlanNoteKind.assumption, 'Searching by meaning: "$semantic"'));
    }

    return SearchPlan(
      dateRange: range,
      minAmount: amounts.min,
      maxAmount: amounts.max,
      includeCategories: include,
      excludeCategories: exclude,
      shopNames: shops,
      personNames: people,
      transactionType: type,
      hasMemo: hasMemo,
      semanticQuery: semantic,
      sort: sort,
      limit: limit,
      notes: notes,
    );
  }

  // ---- patterns -------------------------------------------------------------

  static RegExp _phrase(String phrase) =>
      joinPattern(['(?<![a-z0-9])', RegExp.escape(phrase), '(?![a-z0-9])']);

  static final RegExp _family = RegExp(r'\b(?:my\s+)?family\b');

  static final List<RegExp> _noMemo = [
    RegExp(r'\b(?:without|with\s+no|no)\s+(?:a\s+)?memos?\b'),
  ];
  static final List<RegExp> _withMemo = [
    RegExp(r'\bwhose\s+memos?\s+(?:mentions?|says?|(?:is|are)\s+about|about)\b'),
    RegExp(r'\bmemos?\s+(?:mentioning|about|that\s+mentions?|saying)\b'),
    RegExp(r"\b(?:i\s+|i've\s+)?added\s+(?:a\s+)?memos?(?:\s+to)?\b"),
    RegExp(r'\b(?:with|that\s+ha(?:ve|s)|having)\s+(?:a\s+)?memos?\b'),
  ];

  static const String _sortAlt =
      r'(biggest|largest|most\s+expensive|highest|smallest|cheapest|lowest|oldest|earliest|latest|newest|most\s+recent)';
  static final RegExp _topN = RegExp(r'\btop\s+(\d{1,3})\b');
  static final RegExp _nSorted = joinPattern([r'\b(\d{1,3})\s+', _sortAlt, r'\b']);
  static final RegExp _sortWords = joinPattern([r'\b', _sortAlt, r'\b']);

  static SortOrder _sortFor(String word) => switch (_normalise(word)) {
        'biggest' || 'largest' || 'most expensive' || 'highest' => SortOrder.amountDesc,
        'smallest' || 'cheapest' || 'lowest' => SortOrder.amountAsc,
        'oldest' || 'earliest' => SortOrder.oldest,
        _ => SortOrder.newest,
      };

  static const Map<String, Category> _categoryAliases = {
    'personal care': Category.personalCare,
    'personal-care': Category.personalCare,
    'restaurants': Category.food,
    'restaurant': Category.food,
    'dining': Category.food,
    'meals': Category.food,
    'meal': Category.food,
    'food': Category.food,
    'groceries': Category.grocery,
    'grocery': Category.grocery,
    'clothes': Category.clothing,
    'clothing': Category.clothing,
    'apparel': Category.clothing,
    'bills': Category.bill,
    'bill': Category.bill,
    'utilities': Category.utility,
    'utility': Category.utility,
    'transportation': Category.travel,
    'transport': Category.travel,
    'travel': Category.travel,
    'entertainment': Category.entertainment,
  };

  static final String _categoryAlt = (_categoryAliases.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length)))
      .map((k) => RegExp.escape(k).replaceAll(' ', r'\s+'))
      .join('|');
  static final RegExp _categoryWord =
      joinPattern(['(?<![a-z])(?:', _categoryAlt, ')(?![a-z])']);
  static final RegExp _negatedCategories = joinPattern([
    r'\b(?:excluding|exclude|except(?:\s+for)?|not|without|other\s+than|apart\s+from|but\s+not)\s+',
    r'(?:any\s+|the\s+)?((?:', _categoryAlt, r')(?:\s*(?:,|and|or|nor)\s*(?:', _categoryAlt, r'))*)(?![a-z])',
  ]);

  static final RegExp _transferWords =
      RegExp(r'\b(?:transfers?|transferred|sent\s+to|paid\s+to)\b');
  static final RegExp _purchaseWords =
      RegExp(r'\b(?:purchases?|purchased|bought|buy|shopping)\b');

  static String _normalise(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  // ---- meaning remainder ----------------------------------------------------

  static final RegExp _token = RegExp(r"[a-z0-9]+(?:'[a-z]+)?");
  static final RegExp _digits = RegExp(r'^\d+$');

  /// Free text segments with leading/trailing stopwords trimmed; segments
  /// with no content word are dropped. Original casing is kept.
  static String? _remainder(QueryText text) {
    final parts = <String>[];
    for (final (start, end) in text.freeSegments()) {
      final tokens = _token.allMatches(text.lower.substring(start, end)).toList();
      final content = [
        for (final t in tokens)
          if (!_stopwords.contains(t[0]) && !_digits.hasMatch(t[0]!)) t,
      ];
      if (content.isEmpty) continue;
      parts.add(text.original.substring(start + content.first.start, start + content.last.end));
    }
    final joined = parts.join(' ').trim();
    return joined.isEmpty ? null : joined;
  }

  static const Set<String> _stopwords = {
    'a', 'about', 'after', 'again', 'all', 'also', 'am', 'an', 'and', 'any',
    'are', 'as', 'at', 'back', 'be', 'been', 'but', 'by', 'can', 'could',
    'did', 'do', 'does', 'done', 'each', 'ever', 'everything', 'find', 'for',
    'from', 'get', 'give', 'go', 'got', 'had', 'has', 'have', 'how', 'i',
    "i'd", "i'm", "i've", 'if', 'in', 'into', 'is', 'it', 'its', 'just',
    'let', 'list', 'look', 'made', 'make', 'many', 'me', 'money', 'much',
    'my', 'need', 'of', 'on', 'one', 'ones', 'or', 'our', 'paid', 'pay',
    'payment', 'payments', 'please', 'same', 'search', 'see', 'show', 'so',
    'some', 'spend', 'spending', 'spent', 'stuff', 'than', 'that', 'the',
    'them', 'then', 'these', 'thing', 'things', 'this', 'those', 'to', 'too',
    'top', 'total', 'transaction', 'transactions', 'up', 'us', 'was', 'were',
    'what', 'when', 'where', 'which', 'who', 'why', 'will', 'with', 'would',
    'you', 'your',
  };
}
