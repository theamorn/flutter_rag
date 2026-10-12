import 'categories.dart';

enum TransactionType {
  purchase,
  transfer;

  static TransactionType fromDb(String value) => values.byName(value);
}

/// One outgoing payment. Exactly one of [shopName] / [personName] is set:
/// purchases have a shop, transfers have a person.
class Transaction {
  const Transaction({
    required this.id,
    required this.occurredAt,
    this.shopName,
    this.personName,
    required this.type,
    required this.amountMinor,
    this.currency = 'THB',
    required this.category,
    this.description,
    this.memo,
  });

  final String id;

  /// UTC instant.
  final DateTime occurredAt;
  final String? shopName;
  final String? personName;
  final TransactionType type;

  /// Positive satang, e.g. 129900 = THB 1,299.00.
  final int amountMinor;
  final String currency;
  final Category category;

  /// Payment-provider description, if any.
  final String? description;

  /// User-written reminder; null for ~90% of rows.
  final String? memo;

  String get payeeName => shopName ?? personName!;

  Transaction withMemo(String? memo) => Transaction(
        id: id,
        occurredAt: occurredAt,
        shopName: shopName,
        personName: personName,
        type: type,
        amountMinor: amountMinor,
        currency: currency,
        category: category,
        description: description,
        memo: normalizeMemo(memo),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'shop_name': shopName,
        'person_name': personName,
        'transaction_type': type.name,
        'amount_minor': amountMinor,
        'currency': currency,
        'category': category.dbValue,
        'description': description,
        'memo': memo,
      };

  factory Transaction.fromJson(Map<String, Object?> json) => Transaction(
        id: json['id']! as String,
        occurredAt: DateTime.parse(json['occurred_at']! as String).toUtc(),
        shopName: json['shop_name'] as String?,
        personName: json['person_name'] as String?,
        type: TransactionType.fromDb(json['transaction_type']! as String),
        amountMinor: json['amount_minor']! as int,
        currency: json['currency']! as String,
        category: Category.fromDb(json['category']! as String),
        description: json['description'] as String?,
        memo: json['memo'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is Transaction &&
      other.id == id &&
      other.occurredAt == occurredAt &&
      other.shopName == shopName &&
      other.personName == personName &&
      other.type == type &&
      other.amountMinor == amountMinor &&
      other.currency == currency &&
      other.category == category &&
      other.description == description &&
      other.memo == memo;

  @override
  int get hashCode => Object.hash(id, occurredAt, shopName, personName, type,
      amountMinor, currency, category, description, memo);

  @override
  String toString() => 'Transaction($id, $payeeName, $amountMinor)';
}

/// Empty or whitespace-only memos are stored as null.
String? normalizeMemo(String? memo) {
  final trimmed = memo?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
