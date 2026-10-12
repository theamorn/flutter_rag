import '../search/search_plan.dart';

/// The fields of a [SearchPlan] that the evaluation scores one by one.
enum PlanField {
  dates('dates'),
  minAmount('min amount'),
  minInclusive('min inclusive'),
  maxAmount('max amount'),
  maxInclusive('max inclusive'),
  includeCategories('include categories'),
  excludeCategories('exclude categories'),
  transactionType('transaction type'),
  shops('shops'),
  people('people'),
  hasMemo('has memo'),
  semanticQuery('semantic query'),
  sort('sort'),
  limit('limit');

  const PlanField(this.label);
  final String label;
}

/// Per-field counts for one expected/got pair (or a sum over many).
///
/// - `missing`: the expected plan sets the field and the got plan does not
///   (for set fields: elements of expected that are not in got).
/// - `extra`: the got plan sets the field and the expected plan does not, or
///   sets it to something else (for set fields: elements of got that are not
///   in expected).
///
/// A scalar that is set on both sides with different values counts as one
/// `extra` and no `missing`, so each wrong value shows up exactly once.
class PlanFieldScore {
  const PlanFieldScore({this.missing = 0, this.extra = 0});

  final int missing;
  final int extra;

  bool get isExact => missing == 0 && extra == 0;

  PlanFieldScore operator +(PlanFieldScore other) =>
      PlanFieldScore(missing: missing + other.missing, extra: extra + other.extra);

  @override
  bool operator ==(Object other) =>
      other is PlanFieldScore && other.missing == missing && other.extra == extra;

  @override
  int get hashCode => Object.hash(missing, extra);

  @override
  String toString() => 'PlanFieldScore(missing: $missing, extra: $extra)';
}

PlanFieldScore _scalar<T>(T? expected, T? got, [bool Function(T a, T b)? same]) {
  if (expected == null && got == null) return const PlanFieldScore();
  if (expected != null && got == null) return const PlanFieldScore(missing: 1);
  if (expected == null) return const PlanFieldScore(extra: 1);
  final equal = same != null ? same(expected as T, got as T) : expected == got;
  return equal ? const PlanFieldScore() : const PlanFieldScore(extra: 1);
}

PlanFieldScore _set<T>(Set<T> expected, Set<T> got) => PlanFieldScore(
      missing: expected.difference(got).length,
      extra: got.difference(expected).length,
    );

/// Inclusivity is only compared when both bounds exist with the same amount;
/// otherwise the amount field already reports the difference.
PlanFieldScore _inclusive(AmountBound? expected, AmountBound? got) {
  if (expected == null || got == null || expected.minor != got.minor) {
    return const PlanFieldScore();
  }
  return expected.inclusive == got.inclusive
      ? const PlanFieldScore()
      : const PlanFieldScore(extra: 1);
}

String? _normText(String? s) {
  final t = s?.trim().toLowerCase();
  return t == null || t.isEmpty ? null : t;
}

/// Scores [got] against [expected] on every [PlanField]. Notes are ignored,
/// like `SearchPlan ==`. [SearchPlan.sort] always has a value, so a different
/// sort counts as `extra`.
Map<PlanField, PlanFieldScore> scorePlan(SearchPlan expected, SearchPlan got) => {
      PlanField.dates: _scalar(expected.dateRange, got.dateRange),
      PlanField.minAmount: _scalar(
        expected.minAmount,
        got.minAmount,
        (a, b) => a.minor == b.minor,
      ),
      PlanField.minInclusive: _inclusive(expected.minAmount, got.minAmount),
      PlanField.maxAmount: _scalar(
        expected.maxAmount,
        got.maxAmount,
        (a, b) => a.minor == b.minor,
      ),
      PlanField.maxInclusive: _inclusive(expected.maxAmount, got.maxAmount),
      PlanField.includeCategories: _set(expected.includeCategories, got.includeCategories),
      PlanField.excludeCategories: _set(expected.excludeCategories, got.excludeCategories),
      PlanField.transactionType: _scalar(expected.transactionType, got.transactionType),
      PlanField.shops: _set(expected.shopNames, got.shopNames),
      PlanField.people: _set(expected.personNames, got.personNames),
      PlanField.hasMemo: _scalar(expected.hasMemo, got.hasMemo),
      PlanField.semanticQuery: _scalar(_normText(expected.semanticQuery), _normText(got.semanticQuery)),
      PlanField.sort: expected.sort == got.sort
          ? const PlanFieldScore()
          : const PlanFieldScore(extra: 1),
      PlanField.limit: _scalar(expected.limit, got.limit),
    };

/// Adds [score] into [totals].
void addScores(Map<PlanField, PlanFieldScore> totals, Map<PlanField, PlanFieldScore> score) {
  for (final entry in score.entries) {
    totals[entry.key] = (totals[entry.key] ?? const PlanFieldScore()) + entry.value;
  }
}

/// The fields with any difference, as `dates: missing 1`, `shops: extra 2`.
List<String> describeScore(Map<PlanField, PlanFieldScore> score) => [
      for (final field in PlanField.values)
        if (score[field] case final s? when !s.isExact)
          '${field.label}: ${[
            if (s.missing > 0) 'missing ${s.missing}',
            if (s.extra > 0) 'extra ${s.extra}',
          ].join(', ')}',
    ];

/// A markdown table of per-field totals over [queryCount] scored queries.
String renderFieldTotals(Map<PlanField, PlanFieldScore> totals, int queryCount) => [
      '| field | missing | extra |',
      '|---|---|---|',
      for (final field in PlanField.values)
        '| ${field.label} | ${totals[field]?.missing ?? 0} | ${totals[field]?.extra ?? 0} |',
      '',
      'Over $queryCount queries with a Gemma plan. missing = expected set, got not; '
          'extra = got set, expected not or different (sets: per element).',
    ].join('\n');

/// What happened to one query in an Advanced (Gemma) evaluation run.
enum AdvancedOutcome {
  /// Gemma returned a plan that passed the app's checks.
  plan,

  /// The app's own checks refused Gemma's answer (safe: no wrong rows shown).
  rejected,

  /// The model failed, timed out, or the run itself hit an error.
  errored,

  /// The job was cancelled or superseded, so nothing landed.
  noResult,
}

const List<String> _safeRejectionPrefixes = [
  'Gemma returned filters the app cannot use',
  'Gemma did not preserve',
  'Only THB amounts are supported',
  'Gemma answered without filters',
];

/// Sorts an `AdvancedError` message (as shown to the user in
/// `TransactionSearchController.errors`) into rejected or errored.
AdvancedOutcome classifyAdvancedFailure(String message) =>
    _safeRejectionPrefixes.any(message.startsWith)
        ? AdvancedOutcome.rejected
        : AdvancedOutcome.errored;
