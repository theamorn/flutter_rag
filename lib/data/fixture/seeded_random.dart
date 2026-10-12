/// Deterministic PRNG (mulberry32). The same seed gives the same sequence on
/// every platform and SDK version; `dart:math`'s Random makes no such promise,
/// and the evaluation set depends on a stable dataset.
class SeededRandom {
  SeededRandom(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = _imul(t ^ (t >>> 15), t | 1);
    t ^= (t + _imul(t ^ (t >>> 7), t | 61)) & 0xFFFFFFFF;
    return (t ^ (t >>> 14)) & 0xFFFFFFFF;
  }

  static int _imul(int a, int b) => (a * b) & 0xFFFFFFFF;

  /// Uniform int in [0, max).
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max');
    return nextUint32() % max;
  }

  /// Uniform int in [min, maxInclusive].
  int intInRange(int min, int maxInclusive) =>
      min + nextInt(maxInclusive - min + 1);

  /// Uniform double in (0, 1]. Never 0, so it is safe in pow(u, 1/w).
  double nextDouble() => (nextUint32() + 1) / 4294967296.0;

  bool chance(double p) => nextDouble() <= p;

  T pick<T>(List<T> items) => items[nextInt(items.length)];

  /// An index chosen with probability proportional to [weights].
  int pickWeighted(List<double> weights) {
    final total = weights.fold<double>(0, (a, b) => a + b);
    var x = nextDouble() * total;
    for (var i = 0; i < weights.length; i++) {
      if (weights[i] <= 0) continue;
      x -= weights[i];
      if (x <= 0) return i;
    }
    return weights.lastIndexWhere((w) => w > 0);
  }

  /// Fisher-Yates, in place.
  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }
}
