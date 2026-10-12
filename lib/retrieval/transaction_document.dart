import '../core/bangkok_time.dart';
import '../core/money.dart';
import '../core/transaction.dart';

const int kMaxMemoCharsInDocument = 200;

/// The retrieval text for one transaction (spec §9): memo first, absent
/// fields omitted, and a unique `Ref <id>` suffix so two otherwise
/// identical rows never collapse into one engine source. Always one chunk.
String transactionDocument(Transaction t) {
  final memo = t.memo;
  String? memoText;
  if (memo != null) {
    final clipped = memo.length > kMaxMemoCharsInDocument
        ? memo.substring(0, kMaxMemoCharsInDocument)
        : memo;
    memoText = clipped.replaceAll(RegExp(r'[.\s]+$'), '');
  }
  return [
    if (memoText != null) 'Memo: $memoText',
    t.type == TransactionType.purchase
        ? 'Purchase at ${t.shopName}'
        : 'Transfer to ${t.personName}',
    'Category: ${t.category.label}',
    if (t.description != null) 'Description: ${t.description}',
    'Date: ${formatBangkokDate(t.occurredAt)}',
    'Amount: ${formatThb(t.amountMinor)}',
    'Ref ${t.id}',
  ].join('. ');
}
