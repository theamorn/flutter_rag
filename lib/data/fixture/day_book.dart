import 'seeded_random.dart';

/// Bangkok calendar dates of the dataset as date keys, `DateTime.utc(y, m, d)`.
/// Only the year/month/day fields mean anything. 1,096 days.
List<DateTime> datasetDays() {
  final days = <DateTime>[];
  for (var d = DateTime.utc(2023, 10, 1);
      d.isBefore(DateTime.utc(2026, 10, 1));
      d = DateTime.utc(d.year, d.month, d.day + 1)) {
    days.add(d);
  }
  return days;
}

/// Full-fixture daily capacities: 200 days x 4, 676 x 5, 220 x 6 = 5,500,
/// shuffled with the fixture's RNG.
List<int> dailyCapacities(SeededRandom rng) {
  final caps = [
    ...List.filled(200, 4),
    ...List.filled(676, 5),
    ...List.filled(220, 6),
  ];
  rng.shuffle(caps);
  return caps;
}

/// Tracks how many rows each day still has room for.
class DayBook {
  DayBook(this.days, this.capacity) : _used = List.filled(days.length, 0);

  final List<DateTime> days;
  final List<int> capacity;
  final List<int> _used;

  int indexOf(int year, int month, int day) =>
      DateTime.utc(year, month, day).difference(days.first).inDays;

  bool hasRoom(int day) => _used[day] < capacity[day];

  void take(int day) {
    if (!hasRoom(day)) throw StateError('Day ${days[day]} is full');
    _used[day]++;
  }

  /// A uniformly drawn day in [from, to) with room. If the first draw is full,
  /// redraws among the window's free days (spec §6, stage 2).
  int pickDay(SeededRandom rng, int from, int to) {
    final first = from + rng.nextInt(to - from);
    if (hasRoom(first)) return first;
    final free = [for (var i = from; i < to; i++) if (hasRoom(i)) i];
    if (free.isEmpty) throw StateError('No free day in [$from, $to)');
    return free[rng.nextInt(free.length)];
  }

  /// [from, to) day-index ranges of each calendar month, in order (36).
  List<(int, int)> monthWindows() {
    final out = <(int, int)>[];
    var start = 0;
    for (var i = 1; i <= days.length; i++) {
      if (i == days.length || days[i].month != days[start].month) {
        out.add((start, i));
        start = i;
      }
    }
    return out;
  }
}
