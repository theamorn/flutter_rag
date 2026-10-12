import 'package:flutter/foundation.dart' show setEquals;

import '../core/money.dart';
import '../core/payees.dart';
import '../core/transaction.dart';
import '../search/search_plan.dart';

const String kCandidateSubtotalNote =
    'Relevance-ranked candidates are not proof of all spending for this purpose.';

/// The count and total shown above the list.
class ResultSummary {
  const ResultSummary.exact({
    required this.count,
    required this.totalMinor,
    required this.totalLabel,
  })  : isCandidateSet = false,
        gatedOut = 0,
        notIndexed = 0;

  const ResultSummary.candidates({
    required this.count,
    required this.totalMinor,
    this.gatedOut = 0,
    this.notIndexed = 0,
  })  : isCandidateSet = true,
        totalLabel = '';

  final int count;
  final int totalMinor;
  final String totalLabel;
  final bool isCandidateSet;

  /// Retrieval hits rejected by the cosine gate (semantic only).
  final int gatedOut;

  /// Eligible rows not yet in the search index (semantic only).
  final int notIndexed;

  String get countLabel => isCandidateSet
      ? '$count retrieved candidate${count == 1 ? '' : 's'}'
      : '$count transaction${count == 1 ? '' : 's'}';

  String get totalText => isCandidateSet
      ? 'Subtotal of $count retrieved candidate${count == 1 ? '' : 's'} ${formatThb(totalMinor)}'
      : '$totalLabel ${formatThb(totalMinor)}';
}

/// Label for an exact total, from the plan's payee and type constraints.
String exactTotalLabel(SearchPlan plan) {
  final shops = plan.shopNames;
  final people = plan.personNames;
  if (shops.isEmpty && people.length == 1) {
    return 'Total transferred to ${people.single}';
  }
  if (shops.isEmpty && setEquals(people, kFamilyGroup.toSet())) {
    return 'Total transferred to family';
  }
  if (people.isEmpty && shops.length == 1) return 'Total paid to ${shops.single}';
  return switch (plan.transactionType) {
    TransactionType.purchase => 'Total purchases',
    TransactionType.transfer => 'Total transfers',
    null => 'Total outgoing payments',
  };
}
