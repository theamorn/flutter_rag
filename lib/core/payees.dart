/// Payee names, aliases and the configured family group.
library;

const String kSevenEleven = '7-11';
const String kSushiro = 'Sushiro';
const String kTermsGames = 'TermsGames';
const String kUniqlo = 'Uniqlo';

/// Configured family group: "transfers to my family" means these four.
const List<String> kFamilyGroup = ['Mom', 'Dad', 'Kids', 'Amorn'];

/// Lower-case alias -> canonical shop name (exact stored display name).
const Map<String, String> kShopAliases = {
  '7-11': kSevenEleven,
  '7-eleven': kSevenEleven,
  '7 eleven': kSevenEleven,
  '711': kSevenEleven,
  'seven eleven': kSevenEleven,
  'seven-eleven': kSevenEleven,
  'sushiro': kSushiro,
  'termsgames': kTermsGames,
  'terms games': kTermsGames,
  'uniqlo': kUniqlo,
};

/// Lower-case alias -> canonical person name.
const Map<String, String> kPersonAliases = {
  'mom': 'Mom',
  'mum': 'Mom',
  'mother': 'Mom',
  'dad': 'Dad',
  'father': 'Dad',
  'kids': 'Kids',
  'children': 'Kids',
  'amorn': 'Amorn',
};

enum PayeeKind { shop, person }

class PayeeAlias {
  const PayeeAlias(this.phrase, this.kind, this.canonical);

  /// Lower-case phrase as it appears in a query.
  final String phrase;
  final PayeeKind kind;
  final String canonical;
}

/// Known payees: the distinct names stored in the transaction table plus the
/// fixed aliases above. Built from the database at startup, so the parser
/// recognises exactly the merchants and people the user has paid.
class PayeeDirectory {
  PayeeDirectory({
    required Iterable<String> shops,
    required Iterable<String> people,
  }) {
    for (final s in shops) {
      _shops[s.toLowerCase()] = s;
    }
    for (final p in people) {
      _people[p.toLowerCase()] = p;
    }
    final phrases = <String, PayeeAlias>{};
    void add(String phrase, PayeeKind kind, String canonical) =>
        phrases.putIfAbsent(phrase, () => PayeeAlias(phrase, kind, canonical));
    kShopAliases.forEach((k, v) => add(k, PayeeKind.shop, v));
    kPersonAliases.forEach((k, v) => add(k, PayeeKind.person, v));
    _shops.forEach((k, v) => add(k, PayeeKind.shop, v));
    _people.forEach((k, v) => add(k, PayeeKind.person, v));
    // Longest first, so "terms games" wins over any shorter overlapping alias.
    _phrases = phrases.values.toList()
      ..sort((a, b) => b.phrase.length.compareTo(a.phrase.length));
  }

  final Map<String, String> _shops = {};
  final Map<String, String> _people = {};
  late final List<PayeeAlias> _phrases;

  List<PayeeAlias> get phrases => _phrases;

  Iterable<String> get shopNames => _shops.values;
  Iterable<String> get personNames => _people.values;

  /// Canonical shop name for [text], via alias or case-insensitive name.
  String? resolveShop(String text) {
    final key = text.trim().toLowerCase();
    return kShopAliases[key] ?? _shops[key];
  }

  /// Canonical person name for [text], via alias or case-insensitive name.
  String? resolvePerson(String text) {
    final key = text.trim().toLowerCase();
    return kPersonAliases[key] ?? _people[key];
  }
}
