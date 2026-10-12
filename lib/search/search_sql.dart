import 'package:drift/drift.dart' show Variable;

import 'search_plan.dart';

/// A WHERE expression (without the keyword) plus its positional arguments.
class SqlFilter {
  const SqlFilter(this.where, this.args);

  final String where;
  final List<Object> args;
}

/// The plan's hard filters as SQL. Must select exactly what `planMatches`
/// accepts (tested in transaction_repository_test.dart).
SqlFilter sqlFilterFor(SearchPlan plan, {String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  final clauses = <String>[];
  final args = <Object>[];

  final range = plan.dateRange;
  if (range != null) {
    clauses.add('${p}occurred_at >= ? AND ${p}occurred_at < ?');
    args
      ..add(range.start.millisecondsSinceEpoch)
      ..add(range.end.millisecondsSinceEpoch);
  }
  final min = plan.minAmount;
  if (min != null) {
    clauses.add('${p}amount_minor ${min.inclusive ? '>=' : '>'} ?');
    args.add(min.minor);
  }
  final max = plan.maxAmount;
  if (max != null) {
    clauses.add('${p}amount_minor ${max.inclusive ? '<=' : '<'} ?');
    args.add(max.minor);
  }
  if (plan.includeCategories.isNotEmpty) {
    final values = plan.includeCategories.map((c) => c.dbValue).toList()..sort();
    clauses.add('${p}category IN (${sqlMarks(values.length)})');
    args.addAll(values);
  }
  if (plan.excludeCategories.isNotEmpty) {
    final values = plan.excludeCategories.map((c) => c.dbValue).toList()..sort();
    clauses.add('${p}category NOT IN (${sqlMarks(values.length)})');
    args.addAll(values);
  }
  if (plan.shopNames.isNotEmpty || plan.personNames.isNotEmpty) {
    final parts = <String>[];
    if (plan.shopNames.isNotEmpty) {
      final shops = plan.shopNames.toList()..sort();
      parts.add('${p}shop_name IN (${sqlMarks(shops.length)})');
      args.addAll(shops);
    }
    if (plan.personNames.isNotEmpty) {
      final people = plan.personNames.toList()..sort();
      parts.add('${p}person_name IN (${sqlMarks(people.length)})');
      args.addAll(people);
    }
    clauses.add('(${parts.join(' OR ')})');
  }
  final type = plan.transactionType;
  if (type != null) {
    clauses.add('${p}transaction_type = ?');
    args.add(type.name);
  }
  final hasMemo = plan.hasMemo;
  if (hasMemo != null) {
    clauses.add(hasMemo ? '${p}memo IS NOT NULL' : '${p}memo IS NULL');
  }
  return SqlFilter(clauses.isEmpty ? '1 = 1' : clauses.join(' AND '), args);
}

/// A total order for every sort, so paging never skips or repeats rows.
String sqlOrderFor(SortOrder sort, {String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return switch (sort) {
    SortOrder.oldest => '${p}occurred_at ASC, ${p}id ASC',
    SortOrder.amountDesc => '${p}amount_minor DESC, ${p}occurred_at DESC, ${p}id DESC',
    SortOrder.amountAsc => '${p}amount_minor ASC, ${p}occurred_at DESC, ${p}id DESC',
    SortOrder.newest || SortOrder.relevance => '${p}occurred_at DESC, ${p}id DESC',
  };
}

String sqlMarks(int n) => List.filled(n, '?').join(', ');

/// Positional variables for `customSelect`/`customUpdate`.
List<Variable> sqlVars(List<Object?> args) =>
    [for (final a in args) Variable<Object>(a)];
