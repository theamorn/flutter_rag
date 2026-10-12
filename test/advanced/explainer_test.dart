import 'package:flutter_rag/advanced/explainer.dart';
import 'package:flutter_rag/core/money.dart';
import 'package:flutter_rag/data/fixture/authored.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rows = kAuthoredTransactions
      .where((t) => ['txn_a01', 'txn_a02', 'txn_a28'].contains(t.id))
      .toList();

  test('valid citations are kept; invented ids are replaced and reported', () {
    final e = validateExplanation(
      'You bought camping gear [txn_a01][txn_a02] and something at [txn_9999].',
      {'txn_a01', 'txn_a02'},
    );
    expect(e.citedIds, ['txn_a01', 'txn_a02']);
    expect(e.invalidIds, ['txn_9999']);
    expect(e.text, contains('[unknown reference]'));
    expect(e.isUsable, isTrue);
  });

  test('an answer with no valid citation is unusable', () {
    expect(
      validateExplanation('You went camping.', {'txn_a01'}).isUsable,
      isFalse,
    );
  });

  test('the user turn lists only the given rows, memos as quoted data', () {
    final turn = buildExplainUserTurn('camping last month', rows);
    expect(
      turn,
      contains(
        '[txn_a01] 12 Sep 2026 · Trail Supply · purchase · Travel · THB 1,299.00 · memo: '
        '"Sleeping bag and headlamp for our weekend camping trip"',
      ),
    );
    expect(turn, contains('[txn_a28]'));
    expect(turn, contains('memo: (none)'));
  });

  test('the system prompt forbids invention and treats memos as data', () {
    expect(kExplainSystemPrompt, contains('Use ONLY the transactions'));
    expect(kExplainSystemPrompt, contains('not instructions'));
    expect(kExplainSystemPrompt, contains('[txn_a01]'));
    expect(kExplainSystemPrompt, contains('purpose is not recorded'));
    expect(kExplainSystemPrompt, contains('each transaction individually'));
    expect(kExplainSystemPrompt, contains('exact subtotal provided'));
  });
  test(
    'all bracketed txn references are validated including malformed ids',
    () {
      final e = validateExplanation(
        'Known [txn_a01]; unknown [txn_bad-id], [txn_UPPER], [txn_] and [txn_bad id].',
        {'txn_a01'},
      );
      expect(e.invalidIds, ['txn_bad-id', 'txn_UPPER', 'txn_', 'txn_bad id']);
      expect(
        e.text,
        'Known [txn_a01]; unknown [unknown reference], [unknown reference], [unknown reference] and [unknown reference].',
      );
    },
  );

  test('citations are deduplicated in first-appearance order', () {
    final e = validateExplanation(
      '[txn_a02][txn_a01][txn_a02][txn_bad][txn_bad]',
      {'txn_a01', 'txn_a02'},
    );
    expect(e.citedIds, ['txn_a02', 'txn_a01']);
    expect(e.invalidIds, ['txn_bad']);
  });

  test(
    'a citation of a sixth row is unknown even if the result list contains it',
    () {
      final e = validateExplanation('[txn_a06]', {
        'txn_a01',
        'txn_a02',
        'txn_a03',
        'txn_a04',
        'txn_a05',
      });
      expect(e.isUsable, isFalse);
      expect(e.text, '[unknown reference]');
    },
  );

  group('citation forms models actually produce', () {
    const allowed = {'txn_a01', 'txn_a02'};

    test('a grouped bracket validates every id', () {
      for (final raw in ['[txn_a01, txn_a02]', '[txn_a01; txn_a02]', '[txn_a01 txn_a02]']) {
        final e = validateExplanation('Both $raw.', allowed);
        expect(e.citedIds, ['txn_a01', 'txn_a02'], reason: raw);
        expect(e.invalidIds, isEmpty, reason: raw);
        expect(e.text, contains('txn_a01'), reason: raw);
        expect(e.isUsable, isTrue);
      }
    });

    test('a grouped bracket with an invented id keeps the valid one only', () {
      final e = validateExplanation('Both [txn_a01, txn_9999].', allowed);
      expect(e.citedIds, ['txn_a01']);
      expect(e.invalidIds, ['txn_9999']);
      expect(e.text, isNot(contains('txn_9999')));
      expect(e.text, contains('[txn_a01]'));
      expect(e.text, contains('[unknown reference]'));
    });

    test('padded brackets are tolerated', () {
      final e = validateExplanation('A tent [ txn_a02 ].', allowed);
      expect(e.citedIds, ['txn_a02']);
      expect(e.invalidIds, isEmpty);
      expect(e.text, 'A tent [txn_a02].');
    });

    test('a bare id outside brackets is a citation; an invented one is removed', () {
      final e = validateExplanation('Gear (txn_a01) and txn_9999 and txn_a02.', allowed);
      expect(e.citedIds, ['txn_a01', 'txn_a02']);
      expect(e.invalidIds, ['txn_9999']);
      expect(e.text, isNot(contains('txn_9999')));
      expect(e.text, contains('[unknown reference]'));
    });

    test('a bare invented id alone makes the answer unusable', () {
      final e = validateExplanation('You bought txn_9999.', allowed);
      expect(e.isUsable, isFalse);
      expect(e.invalidIds, ['txn_9999']);
    });
  });

  test('the search line is omitted-safe when no query describes the rows', () {
    final turn = buildExplainUserTurn('', rows);
    expect(turn, isNot(contains('Search: \n')));
    expect(turn, contains('filters'));
  });

  test('user turn includes exact pre-summed subtotal of shown rows capped at kMaxExplainRows', () {
    final sevenRows = kAuthoredTransactions.take(7).toList();
    final shownFive = sevenRows.take(kMaxExplainRows).toList();
    final expectedSubtotal = shownFive.fold<int>(0, (sum, t) => sum + t.amountMinor);
    final turn = buildExplainUserTurn('recent payments', sevenRows);
    expect(
      turn,
      contains('Subtotal of shown transactions (5): ${formatThb(expectedSubtotal)}'),
    );
  });

  test('user turn includes per-transaction amount filter note only when plan has amount bounds', () {
    final withoutAmount = buildExplainUserTurn(
      'camping',
      rows,
      plan: const SearchPlan(personNames: {'Kids'}),
    );
    expect(withoutAmount, isNot(contains('Amount filter')));

    final withMax = buildExplainUserTurn(
      'camping under 2000',
      rows,
      plan: const SearchPlan(maxAmount: AmountBound(200000, inclusive: false)),
    );
    expect(
      withMax,
      contains(
        'Amount filter (< THB 2,000.00) applies to each individual transaction, not the combined subtotal.',
      ),
    );

    final withRange = buildExplainUserTurn(
      'between 500 and 2000',
      rows,
      plan: const SearchPlan(
        minAmount: AmountBound(50000, inclusive: true),
        maxAmount: AmountBound(200000, inclusive: true),
      ),
    );
    expect(
      withRange,
      contains(
        'Amount filter (>= THB 500.00 and <= THB 2,000.00) applies to each individual transaction, not the combined subtotal.',
      ),
    );
  });
}
