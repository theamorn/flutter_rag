import 'package:flutter_rag/data/fixture/seeded_random.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same seed, same sequence; different seed, different sequence', () {
    List<int> run(int seed) {
      final r = SeededRandom(seed);
      return [for (var i = 0; i < 5; i++) r.nextUint32()];
    }

    expect(run(42), run(42));
    expect(run(42), isNot(run(43)));
  });

  test('ranges and doubles stay in bounds', () {
    final r = SeededRandom(7);
    for (var i = 0; i < 1000; i++) {
      final n = r.intInRange(4, 6);
      expect(n >= 4 && n <= 6, isTrue);
      final d = r.nextDouble();
      expect(d > 0 && d <= 1, isTrue);
    }
  });

  test('shuffle is a permutation', () {
    final list = List.generate(50, (i) => i);
    SeededRandom(1).shuffle(list);
    expect(list.toSet(), Set.of(List.generate(50, (i) => i)));
    expect(list, isNot(List.generate(50, (i) => i)));
  });

  test('pickWeighted never returns a zero-weight index', () {
    final r = SeededRandom(3);
    for (var i = 0; i < 500; i++) {
      expect(r.pickWeighted(const [0.0, 1.0, 0.0]), 1);
    }
  });
}
