/// The query plus a consumed mark per character. Rules claim spans in
/// priority order; later rules only see text no earlier rule claimed.
class QueryText {
  QueryText(this.original)
      : lower = _asciiLower(original),
        _used = List.filled(original.length, false);

  final String original;

  /// ASCII-lower-cased copy with identical indices.
  final String lower;
  final List<bool> _used;

  bool isFree(int start, int end) {
    for (var i = start; i < end; i++) {
      if (_used[i]) return false;
    }
    return true;
  }

  void consume(int start, int end) {
    for (var i = start; i < end; i++) {
      _used[i] = true;
    }
  }

  /// Matches of [pattern] on [lower] whose whole span is still free. Each
  /// returned match is consumed.
  List<RegExpMatch> take(RegExp pattern) {
    final taken = <RegExpMatch>[];
    for (final m in pattern.allMatches(lower)) {
      if (m.end > m.start && isFree(m.start, m.end)) {
        consume(m.start, m.end);
        taken.add(m);
      }
    }
    return taken;
  }

  /// Maximal runs of unconsumed characters as (start, end).
  List<(int, int)> freeSegments() {
    final out = <(int, int)>[];
    int? start;
    for (var i = 0; i <= original.length; i++) {
      final free = i < original.length && !_used[i];
      if (free && start == null) start = i;
      if (!free && start != null) {
        out.add((start, i));
        start = null;
      }
    }
    return out;
  }
}

/// Builds a RegExp from pieces (keeps raw-string fragments readable).
RegExp joinPattern(List<String> parts) => RegExp(parts.join());

String _asciiLower(String s) => String.fromCharCodes(
    s.codeUnits.map((c) => c >= 65 && c <= 90 ? c + 32 : c));
