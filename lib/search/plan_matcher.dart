import '../core/transaction.dart';
import 'search_plan.dart';

/// Pure-Dart oracle for a plan's hard filters (spec §7). `search_sql.dart`
/// must select exactly the rows this accepts; Task 8 tests that over the full
/// fixture. Ignores semanticQuery, sort and limit.
bool planMatches(SearchPlan plan, Transaction t) {
  final range = plan.dateRange;
  if (range != null && !range.contains(t.occurredAt)) return false;

  final min = plan.minAmount;
  if (min != null &&
      (min.inclusive ? t.amountMinor < min.minor : t.amountMinor <= min.minor)) {
    return false;
  }
  final max = plan.maxAmount;
  if (max != null &&
      (max.inclusive ? t.amountMinor > max.minor : t.amountMinor >= max.minor)) {
    return false;
  }

  if (plan.includeCategories.isNotEmpty &&
      !plan.includeCategories.contains(t.category)) {
    return false;
  }
  if (plan.excludeCategories.contains(t.category)) return false;

  if (plan.shopNames.isNotEmpty || plan.personNames.isNotEmpty) {
    final payeeMatches =
        (t.shopName != null && plan.shopNames.contains(t.shopName)) ||
            (t.personName != null && plan.personNames.contains(t.personName));
    if (!payeeMatches) return false;
  }

  if (plan.transactionType != null && t.type != plan.transactionType) {
    return false;
  }
  if (plan.hasMemo != null && (t.memo != null) != plan.hasMemo) return false;
  return true;
}
