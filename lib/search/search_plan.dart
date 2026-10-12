import 'package:flutter/foundation.dart' show setEquals;

import '../core/bangkok_time.dart';
import '../core/categories.dart';
import '../core/transaction.dart';

enum SortOrder { newest, oldest, amountDesc, amountAsc, relevance }

/// An amount limit in satang. [inclusive] decides `<=` vs `<` (or `>=`/`>`).
class AmountBound {
  const AmountBound(this.minor, {required this.inclusive});

  final int minor;
  final bool inclusive;

  @override
  bool operator ==(Object other) =>
      other is AmountBound && other.minor == minor && other.inclusive == inclusive;

  @override
  int get hashCode => Object.hash(minor, inclusive);

  @override
  String toString() => 'AmountBound($minor, inclusive: $inclusive)';
}

enum PlanNoteKind { assumption, ambiguous, unused }

/// Shown to the user under the chips. Never a filter.
class PlanNote {
  const PlanNote(this.kind, this.text);

  final PlanNoteKind kind;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is PlanNote && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'PlanNote(${kind.name}: $text)';
}

const Object _unset = Object();

/// The one search contract both interpreters produce (spec §7).
class SearchPlan {
  const SearchPlan({
    this.dateRange,
    this.minAmount,
    this.maxAmount,
    this.includeCategories = const {},
    this.excludeCategories = const {},
    this.shopNames = const {},
    this.personNames = const {},
    this.transactionType,
    this.hasMemo,
    this.semanticQuery,
    this.sort = SortOrder.newest,
    this.limit,
    this.notes = const [],
  });

  static const SearchPlan empty = SearchPlan();

  final DateRange? dateRange;
  final AmountBound? minAmount;
  final AmountBound? maxAmount;
  final Set<Category> includeCategories;
  final Set<Category> excludeCategories;
  final Set<String> shopNames;
  final Set<String> personNames;
  final TransactionType? transactionType;
  final bool? hasMemo;
  final String? semanticQuery;
  final SortOrder sort;
  final int? limit;
  final List<PlanNote> notes;

  bool get hasSemanticIntent =>
      semanticQuery != null && semanticQuery!.trim().isNotEmpty;

  bool get hasHardFilters =>
      dateRange != null ||
      minAmount != null ||
      maxAmount != null ||
      includeCategories.isNotEmpty ||
      excludeCategories.isNotEmpty ||
      shopNames.isNotEmpty ||
      personNames.isNotEmpty ||
      transactionType != null ||
      hasMemo != null;

  /// Omitted arguments keep their value; for nullable fields an explicit
  /// `null` clears them.
  SearchPlan copyWith({
    Object? dateRange = _unset,
    Object? minAmount = _unset,
    Object? maxAmount = _unset,
    Set<Category>? includeCategories,
    Set<Category>? excludeCategories,
    Set<String>? shopNames,
    Set<String>? personNames,
    Object? transactionType = _unset,
    Object? hasMemo = _unset,
    Object? semanticQuery = _unset,
    SortOrder? sort,
    Object? limit = _unset,
    List<PlanNote>? notes,
  }) =>
      SearchPlan(
        dateRange: identical(dateRange, _unset) ? this.dateRange : dateRange as DateRange?,
        minAmount: identical(minAmount, _unset) ? this.minAmount : minAmount as AmountBound?,
        maxAmount: identical(maxAmount, _unset) ? this.maxAmount : maxAmount as AmountBound?,
        includeCategories: includeCategories ?? this.includeCategories,
        excludeCategories: excludeCategories ?? this.excludeCategories,
        shopNames: shopNames ?? this.shopNames,
        personNames: personNames ?? this.personNames,
        transactionType: identical(transactionType, _unset)
            ? this.transactionType
            : transactionType as TransactionType?,
        hasMemo: identical(hasMemo, _unset) ? this.hasMemo : hasMemo as bool?,
        semanticQuery: identical(semanticQuery, _unset)
            ? this.semanticQuery
            : semanticQuery as String?,
        sort: sort ?? this.sort,
        limit: identical(limit, _unset) ? this.limit : limit as int?,
        notes: notes ?? this.notes,
      );

  /// Equality ignores [notes]: two plans that select the same rows are equal.
  @override
  bool operator ==(Object other) =>
      other is SearchPlan &&
      other.dateRange == dateRange &&
      other.minAmount == minAmount &&
      other.maxAmount == maxAmount &&
      setEquals(other.includeCategories, includeCategories) &&
      setEquals(other.excludeCategories, excludeCategories) &&
      setEquals(other.shopNames, shopNames) &&
      setEquals(other.personNames, personNames) &&
      other.transactionType == transactionType &&
      other.hasMemo == hasMemo &&
      other.semanticQuery == semanticQuery &&
      other.sort == sort &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(
        dateRange,
        minAmount,
        maxAmount,
        Object.hashAllUnordered(includeCategories),
        Object.hashAllUnordered(excludeCategories),
        Object.hashAllUnordered(shopNames),
        Object.hashAllUnordered(personNames),
        transactionType,
        hasMemo,
        semanticQuery,
        sort,
        limit,
      );

  @override
  String toString() => 'SearchPlan('
      'date: $dateRange, min: $minAmount, max: $maxAmount, '
      'include: ${includeCategories.map((c) => c.dbValue)}, '
      'exclude: ${excludeCategories.map((c) => c.dbValue)}, '
      'shops: $shopNames, people: $personNames, type: ${transactionType?.name}, '
      'hasMemo: $hasMemo, semantic: $semanticQuery, sort: ${sort.name}, '
      'limit: $limit, notes: $notes)';
}
