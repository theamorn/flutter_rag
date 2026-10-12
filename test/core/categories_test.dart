import 'package:flutter_rag/core/categories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('db values are the eight confirmed categories', () {
    expect(Category.values.map((c) => c.dbValue), [
      'bill', 'food', 'travel', 'entertainment',
      'utility', 'personal_care', 'grocery', 'clothing',
    ]);
  });

  test('fromDb and tryParse', () {
    expect(Category.fromDb('personal_care'), Category.personalCare);
    expect(() => Category.fromDb('gadgets'), throwsArgumentError);
    expect(Category.tryParse('Personal care'), Category.personalCare);
    expect(Category.tryParse(' FOOD '), Category.food);
    expect(Category.tryParse('gadgets'), isNull);
  });

  test('every category has a definition', () {
    expect(kCategoryDefinitions.keys.toSet(), Category.values.toSet());
  });
}
