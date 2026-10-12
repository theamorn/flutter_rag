import '../../core/bangkok_time.dart';
import '../search_plan.dart';
import 'text_spans.dart';

class DateMatch {
  const DateMatch(this.range, this.text);

  final DateRange range;

  /// The query text the range came from.
  final String text;
}

/// Date phrases -> Bangkok calendar ranges, relative to [now] (spec §8 step 5).
class DateRules {
  DateRules({DateTime? now}) : now = now ?? kReferenceNow;

  final DateTime now;

  static const String _month =
      r'(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec)';

  static final RegExp _iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
  static final RegExp _dayMonthYear = joinPattern(
      [r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?', _month, r',?\s+(\d{4})\b']);
  static final RegExp _monthDayYear = joinPattern(
      [r'\b', _month, r'\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b']);
  static final RegExp _monthRange = joinPattern([
    r'\b(?:between|from)\s+', _month, r'(?:\s+(\d{4}))?',
    r'\s+(?:and|to|until|through)\s+', _month, r'(?:\s+(\d{4}))?\b',
  ]);
  static final RegExp _monthYear = joinPattern([r'\b', _month, r'\s+(\d{4})\b']);
  static final RegExp _lastMonth = RegExp(r'\b(?:last|previous|past)\s+month\b');
  static final RegExp _thisMonth = RegExp(r'\bthis\s+month\b');
  static final RegExp _lastYear = RegExp(r'\b(?:last|previous|past)\s+year\b');
  static final RegExp _thisYear = RegExp(r'\bthis\s+year\b');
  static final RegExp _lastN =
      RegExp(r'\b(?:last|past|previous)\s+(\d{1,3})\s+(days?|weeks?|months?)\b');
  static final RegExp _yesterday = RegExp(r'\byesterday\b');
  static final RegExp _today = RegExp(r'\btoday\b');
  static final RegExp _bareMonth = joinPattern(
      [r'\b(?:in|during|for|of)\s+(?:the\s+month\s+of\s+)?', _month, r'\b']);
  static final RegExp _year = RegExp(
      r'(?<![\d,.])(?<!(?:thb|฿)\s?)\b(20\d{2})\b(?![\d,.])(?!\s*(?:thb|baht|฿))');

  ({List<DateMatch> matches, List<PlanNote> notes}) apply(QueryText text) {
    final matches = <DateMatch>[];
    final notes = <PlanNote>[];
    final w = toBangkokWallClock(now);
    final today = startOfBangkokDay(now);
    String phrase(RegExpMatch m) => text.original.substring(m.start, m.end);
    void add(RegExpMatch m, DateRange range) => matches.add(DateMatch(range, phrase(m)));
    void day(RegExpMatch m, int y, int mo, int d) {
      final check = DateTime.utc(y, mo, d);
      if (check.year == y && check.month == mo && check.day == d) {
        add(m, bangkokDay(y, mo, d));
      } else {
        notes.add(PlanNote(PlanNoteKind.ambiguous, 'Not a real date: "${phrase(m)}".'));
      }
    }

    int latestYearFor(int month) => month <= w.month ? w.year : w.year - 1;

    for (final m in text.take(_iso)) {
      day(m, int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }
    for (final m in text.take(_dayMonthYear)) {
      day(m, int.parse(m[3]!), _monthNumber(m[2]!), int.parse(m[1]!));
    }
    for (final m in text.take(_monthDayYear)) {
      day(m, int.parse(m[3]!), _monthNumber(m[1]!), int.parse(m[2]!));
    }
    for (final m in text.take(_monthRange)) {
      final startMonth = _monthNumber(m[1]!);
      final endMonth = _monthNumber(m[3]!);
      final startYearText = m[2];
      final endYearText = m[4];
      int startYear;
      int endYear;
      if (endYearText != null) {
        endYear = int.parse(endYearText);
        startYear = startYearText != null
            ? int.parse(startYearText)
            : (startMonth <= endMonth ? endYear : endYear - 1);
      } else if (startYearText != null) {
        startYear = int.parse(startYearText);
        endYear = endMonth >= startMonth ? startYear : startYear + 1;
      } else {
        endYear = latestYearFor(endMonth);
        startYear = startMonth <= endMonth ? endYear : endYear - 1;
      }
      final range = DateRange(
          bangkokToUtc(startYear, startMonth), bangkokToUtc(endYear, endMonth + 1));
      add(m, range);
      if (startYearText == null && endYearText == null) {
        notes.add(PlanNote(PlanNoteKind.assumption,
            '"${phrase(m)}" = ${formatDateRange(range)} (most recent).'));
      }
    }
    for (final m in text.take(_monthYear)) {
      add(m, bangkokMonth(int.parse(m[2]!), _monthNumber(m[1]!)));
    }
    for (final m in text.take(_lastMonth)) {
      add(m, bangkokMonth(w.year, w.month - 1));
    }
    for (final m in text.take(_thisMonth)) {
      add(m, bangkokMonth(w.year, w.month));
    }
    for (final m in text.take(_lastYear)) {
      add(m, bangkokYear(w.year - 1));
    }
    for (final m in text.take(_thisYear)) {
      add(m, bangkokYear(w.year));
    }
    for (final m in text.take(_lastN)) {
      final n = int.parse(m[1]!);
      final unit = m[2]!;
      if (unit.startsWith('month')) {
        final range = DateRange(bangkokToUtc(w.year, w.month - n), bangkokToUtc(w.year, w.month));
        add(m, range);
        notes.add(PlanNote(PlanNoteKind.assumption,
            'Last $n month${n == 1 ? '' : 's'} = ${formatDateRange(range)} (full calendar months).'));
      } else {
        final days = unit.startsWith('week') ? n * 7 : n;
        add(m, DateRange(today.subtract(Duration(days: days - 1)),
            today.add(const Duration(days: 1))));
      }
    }
    for (final m in text.take(_yesterday)) {
      add(m, DateRange(today.subtract(const Duration(days: 1)), today));
    }
    for (final m in text.take(_today)) {
      add(m, DateRange(today, today.add(const Duration(days: 1))));
    }
    for (final m in text.take(_bareMonth)) {
      final month = _monthNumber(m[1]!);
      final year = latestYearFor(month);
      add(m, bangkokMonth(year, month));
      notes.add(PlanNote(PlanNoteKind.assumption,
          '"${phrase(m).trim()}" = ${kMonthNames[month - 1]} $year (most recent).'));
    }
    for (final m in text.take(_year)) {
      add(m, bangkokYear(int.parse(m[1]!)));
    }
    return (matches: matches, notes: notes);
  }

  static int _monthNumber(String name) =>
      kMonthNames.indexWhere((m) => m.startsWith(name.substring(0, 3))) + 1;
}
