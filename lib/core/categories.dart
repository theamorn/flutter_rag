/// The eight confirmed categories. A category describes the payment's
/// purpose; `TransactionType` separately says purchase vs transfer.
enum Category {
  bill('bill', 'Bill'),
  food('food', 'Food'),
  travel('travel', 'Travel'),
  entertainment('entertainment', 'Entertainment'),
  utility('utility', 'Utility'),
  personalCare('personal_care', 'Personal care'),
  grocery('grocery', 'Grocery'),
  clothing('clothing', 'Clothing');

  const Category(this.dbValue, this.label);

  /// Value stored in SQLite and exchanged with Gemma.
  final String dbValue;

  /// Value shown on chips and cards.
  final String label;

  static Category fromDb(String value) => values.firstWhere(
        (c) => c.dbValue == value,
        orElse: () => throw ArgumentError.value(value, 'category'),
      );

  /// Accepts `personal_care`, `personal care` or `Personal care`.
  static Category? tryParse(String value) {
    final v = value.trim().toLowerCase().replaceAll(' ', '_');
    for (final c in values) {
      if (c.dbValue == v) return c;
    }
    return null;
  }
}

/// Category boundaries, defined once. Shown to Gemma and in the setup docs.
const Map<Category, String> kCategoryDefinitions = {
  Category.bill: 'rent, tuition and school fees, insurance, condo and course fees',
  Category.food: 'restaurants, cafes, takeaway, and meals paid back to people',
  Category.travel: 'transport, flights, hotels, and trip or outdoor gear',
  Category.entertainment: 'cinema, events, games and game top-ups, streaming',
  Category.utility: 'electricity, water, internet and phone bills',
  Category.personalCare: 'pharmacy, salon, gym and health care',
  Category.grocery: 'supermarkets and convenience stores',
  Category.clothing: 'clothes and shoes',
};
