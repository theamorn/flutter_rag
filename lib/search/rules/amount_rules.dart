import 'dart:math' as math;

import '../../core/money.dart';
import '../search_plan.dart';
import 'text_spans.dart';

class AmountParse {
  const AmountParse(this.min, this.max, this.notes);

  final AmountBound? min;
  final AmountBound? max;
  final List<PlanNote> notes;
}

/// "under/over/between/exactly `money`" -> amount bounds (spec §8 step 4).
/// Only THB becomes a filter; anything else is noted, never guessed.
class AmountRules {
  const AmountRules();

  // Groups: 1 currency before, 2 number, 3 fraction, 4 currency after.
  static const String _money =
      r'(?:(thb|฿|\$|usd|€|£|¥)\s?)?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?'
      r'(?:\s?(thb|baht|฿|bucks|usd|dollars?|eur|euros?|€|£|pounds?|yen|¥)(?![a-z]))?';
  static const Set<String> _thb = {'thb', 'baht', '฿'};

  static final RegExp _between =
      joinPattern([r'\bbetween\s+', _money, r'\s+(?:and|to|-)\s+', _money]);
  static final RegExp _under = joinPattern(
      [r'\b(?:under|below|less\s+than|cheaper\s+than|lower\s+than)\s+', _money]);
  static final RegExp _atMost = joinPattern([
    r'\b(?:at\s+most|up\s+to|no\s+more\s+than|not\s+more\s+than|max(?:imum)?(?:\s+of)?)\s+',
    _money,
  ]);
  static final RegExp _over = joinPattern(
      [r'\b(?:over|above|more\s+than|greater\s+than|higher\s+than|exceeding)\s+', _money]);
  static final RegExp _atLeast = joinPattern(
      [r'\b(?:at\s+least|no\s+less\s+than|min(?:imum)?(?:\s+of)?)\s+', _money]);
  static final RegExp _exactly =
      joinPattern([r'\b(?:exactly|for\s+exactly)\s+', _money]);
  // Money that carries a currency but no operator.
  static final RegExp _bare = RegExp(
      r'(?:(thb|฿|\$|usd|€|£|¥)\s?)(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?'
      r'|(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?\s?(thb|baht|฿|bucks|usd|dollars?|eur|euros?|€|£|pounds?|yen|¥)(?![a-z])');

  AmountParse apply(QueryText text) {
    AmountBound? min;
    AmountBound? max;
    final notes = <PlanNote>[];
    String phrase(RegExpMatch m) => text.original.substring(m.start, m.end);

    // Returns the amount in satang, or null (with a note) for non-THB money.
    int? read(RegExpMatch m, int group) {
      final minor = parseBahtToMinor(
          m[group + 2] == null ? m[group + 1]! : '${m[group + 1]}.${m[group + 2]}');
      final currency = (m[group] ?? m[group + 3] ?? '').trim();
      if (minor == null) return null;
      if (currency.isNotEmpty && !_thb.contains(currency)) {
        notes.add(PlanNote(PlanNoteKind.ambiguous,
            'Only THB amounts are supported; ignored "${phrase(m)}".'));
        return null;
      }
      return minor;
    }

    void setMin(AmountBound b, RegExpMatch m) {
      if (min != null) {
        notes.add(PlanNote(PlanNoteKind.ambiguous, 'Ignored a second lower limit "${phrase(m)}".'));
      } else {
        min = b;
      }
    }

    void setMax(AmountBound b, RegExpMatch m) {
      if (max != null) {
        notes.add(PlanNote(PlanNoteKind.ambiguous, 'Ignored a second upper limit "${phrase(m)}".'));
      } else {
        max = b;
      }
    }

    for (final m in text.take(_between)) {
      final a = read(m, 1);
      final b = read(m, 5);
      if (a == null || b == null) continue;
      setMin(AmountBound(math.min(a, b), inclusive: true), m);
      setMax(AmountBound(math.max(a, b), inclusive: true), m);
    }
    for (final m in text.take(_under)) {
      final a = read(m, 1);
      if (a != null) setMax(AmountBound(a, inclusive: false), m);
    }
    for (final m in text.take(_atMost)) {
      final a = read(m, 1);
      if (a != null) setMax(AmountBound(a, inclusive: true), m);
    }
    for (final m in text.take(_over)) {
      final a = read(m, 1);
      if (a != null) setMin(AmountBound(a, inclusive: false), m);
    }
    for (final m in text.take(_atLeast)) {
      final a = read(m, 1);
      if (a != null) setMin(AmountBound(a, inclusive: true), m);
    }
    for (final m in text.take(_exactly)) {
      final a = read(m, 1);
      if (a == null) continue;
      setMin(AmountBound(a, inclusive: true), m);
      setMax(AmountBound(a, inclusive: true), m);
    }
    return AmountParse(min, max, notes);
  }

  /// Notes (and consumes) money with a currency but no operator. Run after
  /// the date rules, so years are never mistaken for amounts.
  List<PlanNote> flagBareAmounts(QueryText text) => [
        for (final m in text.take(_bare))
          _thb.contains((m[1] ?? m[6] ?? '').trim())
              ? PlanNote(PlanNoteKind.ambiguous,
                  'Unclear how to use "${text.original.substring(m.start, m.end)}": say under, over or exactly.')
              : PlanNote(PlanNoteKind.ambiguous,
                  'Only THB amounts are supported; ignored "${text.original.substring(m.start, m.end)}".'),
      ];
}
