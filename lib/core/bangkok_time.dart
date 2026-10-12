/// Asia/Bangkok is UTC+7 all year (Thailand has no daylight saving time).
/// Stored instants are UTC. Calendar logic (days, months, years) uses
/// Bangkok wall-clock time, so "September 2026" starts at
/// 2026-08-31T17:00:00Z.
library;

const Duration kBangkokOffset = Duration(hours: 7);

/// The UTC instant of a Bangkok wall-clock time. Out-of-range fields
/// normalise like [DateTime.utc] (month 13 is January of the next year).
DateTime bangkokToUtc(
  int year, [
  int month = 1,
  int day = 1,
  int hour = 0,
  int minute = 0,
]) =>
    DateTime.utc(year, month, day, hour, minute).subtract(kBangkokOffset);

/// Bangkok wall-clock fields of [instant], as a UTC-flagged DateTime.
/// Read only its fields; it is not the same instant.
DateTime toBangkokWallClock(DateTime instant) =>
    instant.toUtc().add(kBangkokOffset);

/// The fixed demo "now": Saturday 3 October 2026, 12:00 in Bangkok.
/// Relative dates ("last month") resolve against this, never the device clock.
final DateTime kReferenceNow = bangkokToUtc(2026, 10, 3, 12);

/// The dataset covers Bangkok days 1 Oct 2023 to 30 Sep 2026 inclusive.
final DateTime kDatasetStartUtc = bangkokToUtc(2023, 10, 1);
final DateTime kDatasetEndUtc = bangkokToUtc(2026, 10, 1); // exclusive

/// A UTC interval: [start] inclusive, [end] exclusive.
class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime instant) =>
      !instant.isBefore(start) && instant.isBefore(end);

  bool get isEmpty => !start.isBefore(end);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() =>
      'DateRange(${start.toIso8601String()}, ${end.toIso8601String()})';
}

DateRange bangkokDay(int year, int month, int day) => DateRange(
    bangkokToUtc(year, month, day), bangkokToUtc(year, month, day + 1));

DateRange bangkokMonth(int year, int month) =>
    DateRange(bangkokToUtc(year, month), bangkokToUtc(year, month + 1));

DateRange bangkokYear(int year) =>
    DateRange(bangkokToUtc(year), bangkokToUtc(year + 1));

/// Bangkok-midnight UTC instant of the day containing [instant].
DateTime startOfBangkokDay(DateTime instant) {
  final wall = toBangkokWallClock(instant);
  return bangkokToUtc(wall.year, wall.month, wall.day);
}

const List<String> kMonthNames = [
  'january', 'february', 'march', 'april', 'may', 'june', 'july',
  'august', 'september', 'october', 'november', 'december',
];

const List<String> _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `12 Sep 2026` in Bangkok time.
String formatBangkokDate(DateTime instant) {
  final w = toBangkokWallClock(instant);
  return '${w.day} ${_monthShort[w.month - 1]} ${w.year}';
}

/// `12 Sep 2026, 14:20` in Bangkok time.
String formatBangkokDateTime(DateTime instant) {
  final w = toBangkokWallClock(instant);
  final hh = w.hour.toString().padLeft(2, '0');
  final mm = w.minute.toString().padLeft(2, '0');
  return '${formatBangkokDate(instant)}, $hh:$mm';
}

/// `2026-09-12` in Bangkok time (Gemma tool arguments use this).
String formatBangkokIsoDate(DateTime instant) {
  final w = toBangkokWallClock(instant);
  return '${w.year.toString().padLeft(4, '0')}-'
      '${w.month.toString().padLeft(2, '0')}-'
      '${w.day.toString().padLeft(2, '0')}';
}

/// `1 Sep 2026 – 30 Sep 2026`: the end shown is the last included day.
String formatDateRange(DateRange range) {
  final lastDay = range.end.subtract(const Duration(milliseconds: 1));
  final a = formatBangkokDate(range.start);
  final b = formatBangkokDate(lastDay);
  return a == b ? a : '$a – $b';
}
