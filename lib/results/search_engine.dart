import '../data/db/transaction_repository.dart';
import '../perf/stage_timer.dart';
import '../retrieval/semantic_retriever.dart';
import '../search/search_plan.dart';
import 'result_source.dart';
import 'result_summary.dart';

/// What the screen needs after a search: the applied plan, where its rows
/// come from, and the count/total line.
class SearchOutcome {
  const SearchOutcome({
    required this.plan,
    required this.source,
    required this.summary,
    this.notice,
  });

  final SearchPlan plan;
  final ResultSource source;
  final ResultSummary summary;

  /// A one-line message (e.g. "search index still building").
  final String? notice;
}

abstract interface class SearchRunner {
  Future<SearchOutcome> run(SearchPlan plan, StageTimer timer);
}

/// Runs a validated plan: exact plans page SQL; semantic plans page one
/// gated, ranked candidate list (<= 200) inside the same hard filters.
class SearchEngine implements SearchRunner {
  SearchEngine({required this.repo, this.retriever});

  final TransactionRepository repo;
  final SemanticRetriever? retriever;

  @override
  Future<SearchOutcome> run(SearchPlan plan, StageTimer timer) async {
    final retriever = this.retriever;
    if (!plan.hasSemanticIntent || retriever == null) {
      final summary = await timer.time(Stage.sqlFilter, () => repo.summarize(plan));
      return SearchOutcome(
        plan: plan,
        source: ExactResultSource(repo, plan),
        summary: ResultSummary.exact(
          count: summary.count,
          totalMinor: summary.totalMinor,
          totalLabel: exactTotalLabel(plan),
        ),
        notice: plan.hasSemanticIntent
            ? 'Meaning search is not available; showing filter matches only.'
            : null,
      );
    }
    final ranked = await retriever.retrieve(plan, timer);
    final subtotal = await repo.sumAmounts(ranked.ids);
    return SearchOutcome(
      plan: plan,
      source: RankedResultSource(repo, plan, ranked.ids),
      summary: ResultSummary.candidates(
        count: ranked.ids.length,
        totalMinor: subtotal,
        gatedOut: ranked.gatedOut,
        notIndexed: ranked.notIndexed,
      ),
      notice: ranked.notIndexed > 0
          ? 'Search index is still building: ${ranked.notIndexed} of '
              '${ranked.eligible} matching transactions are not searchable by meaning yet.'
          : null,
    );
  }
}
