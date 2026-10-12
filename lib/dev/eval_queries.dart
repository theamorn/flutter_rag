import '../core/bangkok_time.dart';
import '../core/categories.dart';
import '../core/payees.dart';
import '../core/transaction.dart';
import '../search/search_plan.dart';

enum EvalKind { exact, semantic, followUp, memoEdit, noMatch, ambiguous }

/// One evaluation query (spec §13). [expected] is the STANDARD-mode plan
/// (rules); equality ignores notes. [relevant] must appear for recall@5;
/// [acceptable] is never penalised.
class EvalQuery {
  const EvalQuery(
    this.id,
    this.text,
    this.kind, {
    this.expected,
    this.relevant = const {},
    this.acceptable = const {},
    this.followUpOf,
    this.expectedNoteKinds = const {},
  });

  final String id;
  final String text;
  final EvalKind kind;
  final SearchPlan? expected;
  final Set<String> relevant;
  final Set<String> acceptable;
  final String? followUpOf;
  final Set<PlanNoteKind> expectedNoteKinds;
}

const AmountBound _under300 = AmountBound(30000, inclusive: false);
const AmountBound _under3000 = AmountBound(300000, inclusive: false);

final SearchPlan _e02 = SearchPlan(
  dateRange: bangkokMonth(2026, 9),
  maxAmount: _under3000,
  excludeCategories: const {Category.food},
  transactionType: TransactionType.purchase,
  semanticQuery: 'camping',
);

final List<EvalQuery> kEvalQueries = [
  EvalQuery('E01', 'Show food payments under THB 300 last month', EvalKind.exact,
      expected: SearchPlan(
          dateRange: bangkokMonth(2026, 9), maxAmount: _under300, includeCategories: const {Category.food})),
  EvalQuery('E02', 'Find things I bought for camping last month, under THB 3,000, excluding food.',
      EvalKind.semantic,
      expected: _e02, relevant: const {'txn_a01', 'txn_a02', 'txn_a03'}, acceptable: const {'txn_a28'}),
  EvalQuery('E03', 'Show my 7-Eleven payments last month', EvalKind.exact,
      expected: SearchPlan(shopNames: const {'7-11'}, dateRange: bangkokMonth(2026, 9))),
  EvalQuery('E04', 'Find my Sushiro meals in 2025', EvalKind.exact,
      expected: SearchPlan(
          shopNames: const {'Sushiro'}, includeCategories: const {Category.food}, dateRange: bangkokYear(2025))),
  EvalQuery('E05', 'How much did I top up at TermsGames last year?', EvalKind.exact,
      expected: SearchPlan(shopNames: const {'TermsGames'}, dateRange: bangkokYear(2025))),
  EvalQuery('E06', 'Find my Uniqlo purchases', EvalKind.exact,
      expected: const SearchPlan(shopNames: {'Uniqlo'}, transactionType: TransactionType.purchase)),
  EvalQuery('E07', 'Show transfers to Mom last year', EvalKind.exact,
      expected: SearchPlan(
          personNames: const {'Mom'}, transactionType: TransactionType.transfer, dateRange: bangkokYear(2025))),
  EvalQuery('E08', 'Find family transfers whose memos mention helping with the house', EvalKind.semantic,
      expected: SearchPlan(
        personNames: kFamilyGroup.toSet(),
        transactionType: TransactionType.transfer,
        hasMemo: true,
        semanticQuery: 'helping with the house',
      ),
      relevant: const {'txn_a22', 'txn_a24'}, acceptable: const {'txn_a23'}),
  EvalQuery('E09', 'Show all utility payments in September 2026', EvalKind.exact,
      expected: SearchPlan(includeCategories: const {Category.utility}, dateRange: bangkokMonth(2026, 9))),
  EvalQuery('E10', 'Transactions I added a memo to in 2024', EvalKind.exact,
      expected: SearchPlan(hasMemo: true, dateRange: bangkokYear(2024))),
  EvalQuery('E11', 'Payments over THB 10,000 without a memo', EvalKind.exact,
      expected: const SearchPlan(minAmount: AmountBound(1000000, inclusive: false), hasMemo: false)),
  EvalQuery('E12', 'Show payments between THB 1,000 and THB 1,300 in March 2026', EvalKind.exact,
      expected: SearchPlan(
        minAmount: const AmountBound(100000, inclusive: true),
        maxAmount: const AmountBound(130000, inclusive: true),
        dateRange: bangkokMonth(2026, 3),
      )),
  EvalQuery('E13', 'What did I spend on 29 February 2024?', EvalKind.exact,
      expected: SearchPlan(dateRange: bangkokDay(2024, 2, 29))),
  EvalQuery('E14', 'Food payments on 1 September 2026', EvalKind.exact,
      expected: SearchPlan(includeCategories: const {Category.food}, dateRange: bangkokDay(2026, 9, 1))),
  EvalQuery('E15', 'Entertainment payments on 31 December 2025', EvalKind.exact,
      expected: SearchPlan(
          includeCategories: const {Category.entertainment}, dateRange: bangkokDay(2025, 12, 31))),
  EvalQuery('E16', 'Transfers to my kids', EvalKind.exact,
      expected: const SearchPlan(personNames: {'Kids'}, transactionType: TransactionType.transfer)),
  EvalQuery('E17', 'Payments to Amorn excluding bills', EvalKind.exact,
      expected: const SearchPlan(personNames: {'Amorn'}, excludeCategories: {Category.bill})),
  EvalQuery('E18', 'Show grocery and clothing purchases under 500 baht in August 2026', EvalKind.exact,
      expected: SearchPlan(
        includeCategories: const {Category.grocery, Category.clothing},
        maxAmount: const AmountBound(50000, inclusive: false),
        transactionType: TransactionType.purchase,
        dateRange: bangkokMonth(2026, 8),
      )),
  EvalQuery('E19', 'Find the camping gear I bought in 2025', EvalKind.semantic,
      expected: SearchPlan(
          dateRange: bangkokYear(2025), transactionType: TransactionType.purchase, semanticQuery: 'camping gear'),
      relevant: const {'txn_a07', 'txn_a08', 'txn_a09', 'txn_a10'}, acceptable: const {'txn_a11'}),
  EvalQuery('E20', 'Where did I buy a sleeping bag?', EvalKind.semantic,
      expected: const SearchPlan(transactionType: TransactionType.purchase, semanticQuery: 'sleeping bag'),
      relevant: const {'txn_a01'}, acceptable: const {'txn_a07'}),
  EvalQuery('E21', 'Money I paid Alex back for the group trip', EvalKind.semantic,
      expected: const SearchPlan(personNames: {'Alex'}, semanticQuery: 'group trip'),
      relevant: const {'txn_a21'}),
  EvalQuery('E22', 'Deposit for the apartment', EvalKind.semantic,
      expected: const SearchPlan(semanticQuery: 'Deposit for the apartment'),
      relevant: const {'txn_a27'}, acceptable: const {'txn_a26'}),
  EvalQuery('E23', 'School fees for the kids', EvalKind.semantic,
      expected: const SearchPlan(personNames: {'Kids'}, semanticQuery: 'School fees'),
      relevant: const {'txn_a25'}),
  EvalQuery('E24', 'Party supplies for the housewarming', EvalKind.semantic,
      expected: const SearchPlan(semanticQuery: 'Party supplies for the housewarming'),
      relevant: const {'txn_a29'}),
  EvalQuery('E25', 'housewarming', EvalKind.memoEdit,
      expected: const SearchPlan(semanticQuery: 'housewarming'), relevant: const {'txn_a29'}),
  EvalQuery('E26', 'Scuba diving lessons', EvalKind.noMatch,
      expected: const SearchPlan(semanticQuery: 'Scuba diving lessons')),
  EvalQuery('E27', 'Sushiro payments in 2022', EvalKind.noMatch,
      expected: SearchPlan(shopNames: const {'Sushiro'}, dateRange: bangkokYear(2022))),
  EvalQuery('E28', 'Camping purchases excluding travel', EvalKind.semantic,
      expected: const SearchPlan(
          transactionType: TransactionType.purchase,
          excludeCategories: {Category.travel},
          semanticQuery: 'Camping'),
      relevant: const {'txn_a03', 'txn_a09'}, acceptable: const {'txn_a04', 'txn_a11'}),
  EvalQuery('E29', 'Same purchases, but go back one year and include the month before it too',
      EvalKind.followUp,
      followUpOf: 'E02',
      expected: _e02.copyWith(dateRange: DateRange(bangkokToUtc(2025, 8), bangkokToUtc(2025, 10))),
      relevant: const {'txn_a07', 'txn_a08', 'txn_a09'}),
  const EvalQuery('E30', 'Payments of 500 baht', EvalKind.ambiguous,
      expected: SearchPlan.empty, expectedNoteKinds: {PlanNoteKind.ambiguous}),
  EvalQuery('E31', 'Payments over 100 dollars last year', EvalKind.ambiguous,
      expected: SearchPlan(dateRange: bangkokYear(2025)), expectedNoteKinds: const {PlanNoteKind.ambiguous}),
  EvalQuery('E32', 'Gear for sleeping outdoors', EvalKind.semantic,
      expected: const SearchPlan(semanticQuery: 'Gear for sleeping outdoors'),
      relevant: const {'txn_a01', 'txn_a07'}, acceptable: const {'txn_a02', 'txn_a30'}),
];

EvalQuery evalQuery(String id) => kEvalQueries.firstWhere((q) => q.id == id);

/// Extra no-match probes for the gate calibration (not in the 32).
const List<String> kNoMatchProbes = [
  'Scuba diving lessons',
  'Piano tuition',
  'Car tyres',
  'Dog grooming',
  'Wedding ring',
  'Gold necklace',
];
