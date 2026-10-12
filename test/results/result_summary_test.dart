import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/core/transaction.dart';
import 'package:flutter_rag/results/result_summary.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact totals are labelled by the query', () {
    expect(exactTotalLabel(const SearchPlan(personNames: {'Mom'}, transactionType: TransactionType.transfer)),
        'Total transferred to Mom');
    expect(exactTotalLabel(SearchPlan(personNames: kFamilyGroup.toSet())), 'Total transferred to family');
    expect(exactTotalLabel(const SearchPlan(shopNames: {'7-11'})), 'Total paid to 7-11');
    expect(exactTotalLabel(const SearchPlan(transactionType: TransactionType.purchase)), 'Total purchases');
    expect(exactTotalLabel(SearchPlan.empty), 'Total outgoing payments');
  });

  test('exact and candidate summaries read differently', () {
    const exact = ResultSummary.exact(count: 1, totalMinor: 129900, totalLabel: 'Total purchases');
    expect(exact.countLabel, '1 transaction');
    expect(exact.totalText, 'Total purchases THB 1,299.00');
    const cand = ResultSummary.candidates(count: 3, totalMinor: 438900);
    expect(cand.isCandidateSet, isTrue);
    expect(cand.countLabel, '3 retrieved candidates');
    expect(cand.totalText, 'Subtotal of 3 retrieved candidates THB 4,389.00');
  });
}
