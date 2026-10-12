/// Money is always an integer count of satang (THB minor units):
/// `129900` is THB 1,299.00. Never use doubles for stored amounts.
library;

/// Formats minor units as `THB 1,299.00`.
String formatThb(int minor) {
  final sign = minor < 0 ? '-' : '';
  final abs = minor.abs();
  final baht = (abs ~/ 100).toString();
  final satang = (abs % 100).toString().padLeft(2, '0');
  final grouped = StringBuffer();
  for (var i = 0; i < baht.length; i++) {
    if (i > 0 && (baht.length - i) % 3 == 0) grouped.write(',');
    grouped.write(baht[i]);
  }
  return '${sign}THB $grouped.$satang';
}

/// Parses `1,299`, `1299.5` or `3,000.00` into minor units.
/// Returns null for anything that is not a plain positive number.
int? parseBahtToMinor(String text) {
  final match = RegExp(r'^(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?$')
      .firstMatch(text.trim());
  if (match == null) return null;
  final whole = int.parse(match.group(1)!.replaceAll(',', ''));
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(fraction);
}
