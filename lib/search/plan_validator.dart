import '../core/money.dart';
import '../core/payees.dart';
import '../core/transaction.dart';
import 'search_plan.dart';

class PlanValidation {
  const PlanValidation._(this.plan, this.errors);

  factory PlanValidation.ok(SearchPlan plan) => PlanValidation._(plan, const []);
  factory PlanValidation.invalid(List<String> errors) =>
      PlanValidation._(null, errors);

  final SearchPlan? plan;
  final List<String> errors;

  bool get isValid => plan != null;
}

/// Checks any plan (rules, chips or Gemma) and returns a canonical copy:
/// payee aliases resolved, semantic text trimmed, sort normalised.
class PlanValidator {
  const PlanValidator(this.directory);

  final PayeeDirectory directory;

  static const int maxLimit = 200;
  static const int maxSemanticChars = 200;

  PlanValidation validate(SearchPlan plan) {
    final errors = <String>[];

    final range = plan.dateRange;
    if (range != null && range.isEmpty) errors.add('The date range is empty.');

    final min = plan.minAmount;
    final max = plan.maxAmount;
    if ((min != null && min.minor < 0) || (max != null && max.minor < 0)) {
      errors.add('Amounts must be positive.');
    }
    if (min != null && max != null) {
      final satisfiable = min.minor < max.minor ||
          (min.minor == max.minor && min.inclusive && max.inclusive);
      if (!satisfiable) {
        errors.add('No amount is ${min.inclusive ? 'at least' : 'over'} '
            '${formatThb(min.minor)} and ${max.inclusive ? 'at most' : 'under'} '
            '${formatThb(max.minor)}.');
      }
    }

    for (final c in plan.includeCategories.intersection(plan.excludeCategories)) {
      errors.add('${c.label} is both included and excluded.');
    }

    final shops = <String>{};
    for (final s in plan.shopNames) {
      final resolved = directory.resolveShop(s);
      if (resolved == null) {
        errors.add('Unknown shop "$s".');
      } else {
        shops.add(resolved);
      }
    }
    final people = <String>{};
    for (final p in plan.personNames) {
      final resolved = directory.resolvePerson(p);
      if (resolved == null) {
        errors.add('Unknown person "$p".');
      } else {
        people.add(resolved);
      }
    }

    final type = plan.transactionType;
    if (type == TransactionType.transfer && shops.isNotEmpty && people.isEmpty) {
      errors.add('Shops only receive purchases, not transfers.');
    }
    if (type == TransactionType.purchase && people.isNotEmpty && shops.isEmpty) {
      errors.add('People only receive transfers, not purchases.');
    }

    final limit = plan.limit;
    if (limit != null && (limit < 1 || limit > maxLimit)) {
      errors.add('Limit must be between 1 and $maxLimit.');
    }

    var semantic = plan.semanticQuery?.trim();
    if (semantic != null && semantic.isEmpty) semantic = null;
    if (semantic != null && semantic.length > maxSemanticChars) {
      errors.add('The meaning search text is longer than $maxSemanticChars characters.');
    }

    if (errors.isNotEmpty) return PlanValidation.invalid(errors);

    // Meaning searches are always relevance-ranked; exact searches never are.
    final sort = semantic != null
        ? SortOrder.relevance
        : (plan.sort == SortOrder.relevance ? SortOrder.newest : plan.sort);
    return PlanValidation.ok(plan.copyWith(
      shopNames: shops,
      personNames: people,
      semanticQuery: semantic,
      sort: sort,
    ));
  }
}
