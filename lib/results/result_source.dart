import 'dart:math' as math;

import '../core/transaction.dart';
import '../data/db/transaction_repository.dart';
import '../search/plan_matcher.dart';
import '../search/search_plan.dart';

class PageResult {
  const PageResult(this.rows, {required this.reachedEnd});

  final List<Transaction> rows;

  /// True when no rows exist after this page.
  final bool reachedEnd;
}

/// Something the pager can read pages from.
abstract interface class ResultSource {
  Future<PageResult> fetch(int offset, int limit);
}

/// Exact search: SQL order and paging over every matching row.
class ExactResultSource implements ResultSource {
  ExactResultSource(this.repo, this.plan);

  final TransactionRepository repo;
  final SearchPlan plan;

  @override
  Future<PageResult> fetch(int offset, int limit) async {
    final rows = await repo.page(plan, offset: offset, limit: limit);
    return PageResult(rows, reachedEnd: rows.length < limit);
  }
}

/// Semantic search: pages through one gated, ranked id list (<= 200) locally.
class RankedResultSource implements ResultSource {
  RankedResultSource(this.repo, this.plan, this.rankedIds);

  final TransactionRepository repo;
  final SearchPlan plan;
  final List<String> rankedIds;

  @override
  Future<PageResult> fetch(int offset, int limit) async {
    if (offset >= rankedIds.length) {
      return const PageResult([], reachedEnd: true);
    }
    final end = math.min(offset + limit, rankedIds.length);
    final rows = await repo.getByIds(rankedIds.sublist(offset, end));
    // Re-check the hard filters: a memo edit can change eligibility.
    return PageResult(
      [for (final t in rows) if (planMatches(plan, t)) t],
      reachedEnd: end >= rankedIds.length,
    );
  }
}
