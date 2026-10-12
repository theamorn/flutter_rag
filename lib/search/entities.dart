import '../core/bangkok_time.dart';

enum DateGranularity { year, month, week, day, hour, minute, second, unknown }

/// An entity found by ML Kit (or a fake), with its character span in the
/// query. Our own type, so rules are testable without the plugin.
sealed class ExtractedEntity {
  const ExtractedEntity(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

class ExtractedDate extends ExtractedEntity {
  const ExtractedDate(super.start, super.end, super.text,
      {required this.instant, required this.granularity});

  final DateTime instant;
  final DateGranularity granularity;

  /// ML Kit gives a timestamp plus a granularity, not a range; the app owns
  /// the interval (spec §8 step 9). Finer than a day = the containing day.
  DateRange toRange() {
    final w = toBangkokWallClock(instant);
    return switch (granularity) {
      DateGranularity.year => bangkokYear(w.year),
      DateGranularity.month => bangkokMonth(w.year, w.month),
      DateGranularity.week => DateRange(startOfBangkokDay(instant),
          startOfBangkokDay(instant).add(const Duration(days: 7))),
      _ => bangkokDay(w.year, w.month, w.day),
    };
  }
}

class ExtractedMoney extends ExtractedEntity {
  const ExtractedMoney(super.start, super.end, super.text,
      {required this.minor, required this.currency});

  final int minor;

  /// As written (ML Kit `unnormalizedCurrency`).
  final String currency;

  bool get isThb {
    final c = currency.trim().toLowerCase();
    return c.isEmpty || c == 'thb' || c == 'baht' || c == '฿';
  }
}

abstract interface class EntitySource {
  Future<List<ExtractedEntity>> extract(String text);
  Future<void> close();
}

/// Rules only (tests, and the fallback when ML Kit is unavailable).
class NoEntitySource implements EntitySource {
  const NoEntitySource();

  @override
  Future<List<ExtractedEntity>> extract(String text) async => const [];

  @override
  Future<void> close() async {}
}
