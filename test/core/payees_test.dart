import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dir = PayeeDirectory(
    shops: ['7-11', 'Sushiro', 'TermsGames', 'Uniqlo', 'Big Mart'],
    people: ['Mom', 'Dad', 'Kids', 'Amorn', 'Alex'],
  );

  test('shop aliases resolve to stored display names', () {
    expect(dir.resolveShop('7-Eleven'), '7-11');
    expect(dir.resolveShop('711'), '7-11');
    expect(dir.resolveShop('terms games'), 'TermsGames');
    expect(dir.resolveShop('UNIQLO'), 'Uniqlo');
    expect(dir.resolveShop('big mart'), 'Big Mart');
    expect(dir.resolveShop('Starbucks'), isNull);
  });

  test('person aliases resolve', () {
    expect(dir.resolvePerson('mother'), 'Mom');
    expect(dir.resolvePerson('children'), 'Kids');
    expect(dir.resolvePerson('alex'), 'Alex');
    expect(dir.resolvePerson('Bob'), isNull);
  });

  test('phrases are longest first and include stored names', () {
    final phrases = dir.phrases.map((p) => p.phrase).toList();
    expect(phrases, contains('big mart'));
    for (var i = 1; i < phrases.length; i++) {
      expect(phrases[i - 1].length >= phrases[i].length, isTrue);
    }
  });

  test('the family group is Mom, Dad, Kids, Amorn', () {
    expect(kFamilyGroup, ['Mom', 'Dad', 'Kids', 'Amorn']);
  });
}
