import 'package:flutter_rag/advanced/advanced_controller.dart';
import 'package:flutter_rag/advanced/transfer_drafter.dart';
import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_rag/data/fixture/authored.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final momRent = kAuthoredTransactions.firstWhere((t) => t.id == 'txn_a24');
  final dadElec = kAuthoredTransactions.firstWhere((t) => t.id == 'txn_a23');
  final tentPurchase = kAuthoredTransactions.firstWhere((t) => t.id == 'txn_a02');

  group('buildDraftTransferUserTurn', () {
    test('lists only transfer rows up to kMaxDraftRows with formatted THB', () {
      final prompt = buildDraftTransferUserTurn(
        'Send Mom the same amount for October rent',
        [tentPurchase, momRent, dadElec],
      );
      expect(prompt, contains('Request: Send Mom the same amount for October rent'));
      expect(prompt, contains('Today: 2026-10-03 (October 2026)'));
      expect(prompt, contains('[txn_a24] 2 Sep 2026 · recipient: Mom · category: Bill · amount: THB 10,000.00'));
      expect(prompt, contains('[txn_a23] 3 Nov 2025 · recipient: Dad · category: Utility · amount: THB 2,300.00'));
      expect(prompt, isNot(contains('txn_a02')));
    });
  });

  group('validateTransferDraft deterministic post-hook', () {
    test('accepts valid tool call and copies satang amount and recipient from SQLite row', () {
      final draft = validateTransferDraft(
        {
          'source_txn_id': '[txn_a24]',
          'recipient': 'mom',
          'new_memo': 'My share of October rent for the family home',
          // Even if the model tried to pass an amount, it is ignored:
          'amount': 999999,
        },
        [momRent, dadElec],
      );
      expect(draft.sourceTxnId, 'txn_a24');
      expect(draft.recipient, 'Mom');
      expect(draft.amountMinor, 1000000); // exact THB 10,000.00 from SQLite
      expect(draft.category, Category.bill);
      expect(draft.newMemo, 'My share of October rent for the family home');
      expect(draft.previousMemo, 'My share of September rent for the family home');
      expect(draft.sourceOccurredAt, bangkokToUtc(2026, 9, 2, 7, 45));
    });

    test('rejects unknown source_txn_id not in retrieved rows', () {
      expect(
        () => validateTransferDraft(
          {
            'source_txn_id': 'txn_9999',
            'recipient': 'Mom',
            'new_memo': 'October rent',
          },
          [momRent],
        ),
        throwsA(
          isA<AdvancedError>().having(
            (e) => e.message,
            'message',
            contains('not in the retrieved results'),
          ),
        ),
      );
    });

    test('rejects purchase transaction passed as transfer source', () {
      expect(
        () => validateTransferDraft(
          {
            'source_txn_id': 'txn_a02',
            'recipient': 'Outdoor Base',
            'new_memo': 'Tent repeat',
          },
          [tentPurchase],
        ),
        throwsA(
          isA<AdvancedError>().having(
            (e) => e.message,
            'message',
            contains('purchase, not a transfer'),
          ),
        ),
      );
    });

    test('rejects mismatched recipient (prevents redirecting transfer to another person)', () {
      expect(
        () => validateTransferDraft(
          {
            'source_txn_id': 'txn_a24',
            'recipient': 'Dad',
            'new_memo': 'October rent',
          },
          [momRent, dadElec],
        ),
        throwsA(
          isA<AdvancedError>().having(
            (e) => e.message,
            'message',
            contains('does not match source transfer recipient "Mom"'),
          ),
        ),
      );
    });

    test('falls back to previous memo and caps at 200 chars', () {
      final fallback = validateTransferDraft(
        {
          'source_txn_id': 'txn_a24',
          'recipient': 'Mom',
          'new_memo': '   ',
        },
        [momRent],
      );
      expect(fallback.newMemo, momRent.memo);

      final longMemo = 'A' * 250;
      final capped = validateTransferDraft(
        {
          'source_txn_id': 'txn_a24',
          'recipient': 'Mom',
          'new_memo': longMemo,
        },
        [momRent],
      );
      expect(capped.newMemo.length, 200);
    });
  });
}
