import '../core/bangkok_time.dart';
import '../core/categories.dart';
import '../core/payees.dart';
import '../core/transaction.dart';
import '../search/search_plan.dart';
import 'gemma_tool.dart';

class ArgsConversion {
  const ArgsConversion(this.plan, this.errors);

  final SearchPlan? plan;
  final List<String> errors;
  bool get isValid => plan != null && errors.isEmpty;
}

/// Converts a tool call to a plan. With [current], the call is a delta.
/// Invalid input yields errors and no partially applied plan.
ArgsConversion planFromToolArgs(
  Map<String, dynamic> args, {
  SearchPlan? current,
  required PayeeDirectory directory,
}) {
  final errors = <String>[];
  final properties =
      kSearchTool.parameters['properties'] as Map<String, dynamic>;
  for (final key in args.keys) {
    if (!properties.containsKey(key)) errors.add('Unknown tool field "$key".');
  }

  var plan = current ?? SearchPlan.empty;
  for (final field in _stringList(args, 'clear', errors)) {
    switch (field) {
      case 'dates':
        plan = plan.copyWith(dateRange: null);
      case 'amount':
        plan = plan.copyWith(minAmount: null, maxAmount: null);
      case 'categories':
        plan = plan.copyWith(
          includeCategories: const {},
          excludeCategories: const {},
        );
      case 'payees':
        plan = plan.copyWith(shopNames: const {}, personNames: const {});
      case 'type':
        plan = plan.copyWith(transactionType: null);
      case 'memo':
        plan = plan.copyWith(hasMemo: null);
      case 'semantic':
        plan = plan.copyWith(semanticQuery: null);
      case 'sort':
        plan = plan.copyWith(sort: SortOrder.newest);
      case 'limit':
        plan = plan.copyWith(limit: null);
      default:
        errors.add('Unknown field to clear: "$field".');
    }
  }

  final from = _date(args, 'date_from', errors);
  final to = _date(args, 'date_to', errors);
  if (from != null || to != null) {
    final start = from == null
        ? (plan.dateRange?.start ?? kDatasetStartUtc)
        : bangkokToUtc(from.year, from.month, from.day);
    final end = to == null
        ? (plan.dateRange?.end ?? kDatasetEndUtc)
        : bangkokToUtc(to.year, to.month, to.day + 1);
    if (!start.isBefore(end)) {
      errors.add('date_from must be on or before date_to.');
    } else {
      plan = plan.copyWith(dateRange: DateRange(start, end));
    }
  }

  for (final prefix in ['min', 'max']) {
    final amountKey = 'amount_$prefix';
    final inclusiveKey = 'amount_${prefix}_inclusive';
    final amount = _amount(args, amountKey, errors);
    final inclusive = _boolean(args, inclusiveKey, errors);
    final existing = prefix == 'min' ? plan.minAmount : plan.maxAmount;
    if (amount != null || inclusive != null) {
      if (amount == null && existing == null && inclusive != null) {
        errors.add('$inclusiveKey needs $amountKey.');
      } else if (amount != null || existing != null) {
        final bound = AmountBound(
          amount ?? existing!.minor,
          inclusive: inclusive ?? existing?.inclusive ?? false,
        );
        plan = prefix == 'min'
            ? plan.copyWith(minAmount: bound)
            : plan.copyWith(maxAmount: bound);
      }
    }
  }

  if (args.containsKey('include_categories')) {
    plan = plan.copyWith(
      includeCategories: _categories(args, 'include_categories', errors),
    );
  }
  if (args.containsKey('exclude_categories')) {
    plan = plan.copyWith(
      excludeCategories: _categories(args, 'exclude_categories', errors),
    );
  }

  if (args.containsKey('shops')) {
    final shops = <String>{};
    for (final raw in _stringList(args, 'shops', errors)) {
      final name = directory.resolveShop(raw);
      if (name == null) {
        errors.add('Unknown shop "$raw".');
      } else {
        shops.add(name);
      }
    }
    plan = plan.copyWith(shopNames: shops);
  }
  if (args.containsKey('people')) {
    final people = <String>{};
    for (final raw in _stringList(args, 'people', errors)) {
      final name = directory.resolvePerson(raw);
      if (name == null) {
        errors.add('Unknown person "$raw".');
      } else {
        people.add(name);
      }
    }
    plan = plan.copyWith(personNames: people);
  }
  final family = _boolean(args, 'family', errors);
  if (family == true) {
    plan = plan.copyWith(
      personNames: {...plan.personNames, ...kFamilyGroup},
      transactionType: TransactionType.transfer,
    );
  }

  if (args.containsKey('transaction_type')) {
    switch (args['transaction_type']) {
      case 'purchase':
        plan = plan.copyWith(transactionType: TransactionType.purchase);
      case 'transfer':
        plan = plan.copyWith(transactionType: TransactionType.transfer);
      default:
        errors.add('Unknown transaction_type "${args['transaction_type']}".');
    }
  }
  final hasMemo = _boolean(args, 'has_memo', errors);
  if (hasMemo != null) plan = plan.copyWith(hasMemo: hasMemo);

  if (args.containsKey('semantic_query')) {
    final value = args['semantic_query'];
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.length > 200) {
        errors.add('semantic_query is longer than 200 characters.');
      }
      plan = plan.copyWith(semanticQuery: trimmed.isEmpty ? null : trimmed);
    } else {
      errors.add('semantic_query must be text.');
    }
  }

  if (args.containsKey('sort')) {
    final sort = switch (args['sort']) {
      'newest' => SortOrder.newest,
      'oldest' => SortOrder.oldest,
      'amount_desc' => SortOrder.amountDesc,
      'amount_asc' => SortOrder.amountAsc,
      'relevance' => SortOrder.relevance,
      _ => null,
    };
    if (sort == null) {
      errors.add('Unknown sort "${args['sort']}".');
    } else {
      plan = plan.copyWith(sort: sort);
    }
  }
  if (args.containsKey('limit')) {
    final value = args['limit'];
    if (value is int && value >= 1 && value <= 200) {
      plan = plan.copyWith(limit: value);
    } else {
      errors.add('limit must be a whole number from 1 to 200.');
    }
  }

  final min = plan.minAmount;
  final max = plan.maxAmount;
  if (min != null &&
      max != null &&
      (min.minor > max.minor ||
          (min.minor == max.minor && !(min.inclusive && max.inclusive)))) {
    errors.add('Amount bounds leave no possible amount.');
  }
  if (plan.includeCategories.intersection(plan.excludeCategories).isNotEmpty) {
    errors.add('A category cannot be both included and excluded.');
  }
  if (errors.isNotEmpty) return ArgsConversion(null, errors);
  return ArgsConversion(
    plan.copyWith(
      notes: const [
        PlanNote(
          PlanNoteKind.assumption,
          'Interpreted by Gemma 4 E2B on this phone.',
        ),
      ],
    ),
    const [],
  );
}

Map<String, Object> planToToolArgs(SearchPlan plan) {
  final range = plan.dateRange;
  final min = plan.minAmount;
  final max = plan.maxAmount;
  return {
    if (range != null) 'date_from': formatBangkokIsoDate(range.start),
    if (range != null)
      'date_to': formatBangkokIsoDate(
        range.end.subtract(const Duration(milliseconds: 1)),
      ),
    if (min != null) 'amount_min': _bahtNumber(min.minor),
    if (min != null) 'amount_min_inclusive': min.inclusive,
    if (max != null) 'amount_max': _bahtNumber(max.minor),
    if (max != null) 'amount_max_inclusive': max.inclusive,
    if (plan.includeCategories.isNotEmpty)
      'include_categories': [for (final c in plan.includeCategories) c.dbValue]
        ..sort(),
    if (plan.excludeCategories.isNotEmpty)
      'exclude_categories': [for (final c in plan.excludeCategories) c.dbValue]
        ..sort(),
    if (plan.shopNames.isNotEmpty) 'shops': plan.shopNames.toList()..sort(),
    if (plan.personNames.isNotEmpty)
      'people': plan.personNames.toList()..sort(),
    if (plan.transactionType != null)
      'transaction_type': plan.transactionType!.name,
    if (plan.hasMemo != null) 'has_memo': plan.hasMemo!,
    if (plan.semanticQuery != null) 'semantic_query': plan.semanticQuery!,
    if (plan.sort != SortOrder.newest)
      'sort': switch (plan.sort) {
        SortOrder.oldest => 'oldest',
        SortOrder.amountDesc => 'amount_desc',
        SortOrder.amountAsc => 'amount_asc',
        SortOrder.relevance => 'relevance',
        SortOrder.newest => 'newest',
      },
    if (plan.limit != null) 'limit': plan.limit!,
  };
}

num _bahtNumber(int minor) {
  if (minor < 0 || minor > _maxInt64Minor) {
    throw RangeError.value(
      minor,
      'minor',
      'Amount is outside 64-bit satang range',
    );
  }
  if (minor % 100 == 0) return minor ~/ 100;
  final text = '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
  final number = num.parse(text);
  if (_parseExactBaht(number.toString()) != minor) {
    throw RangeError.value(
      minor,
      'minor',
      'Cannot encode amount exactly as a JSON number',
    );
  }
  return number;
}

DateTime? _date(Map<String, dynamic> args, String key, List<String> errors) {
  if (!args.containsKey(key)) return null;
  final value = args[key];
  final match = value is String
      ? RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value)
      : null;
  if (match == null) {
    errors.add('$key must be YYYY-MM-DD.');
    return null;
  }
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    errors.add('$key is not a real date: "$value".');
    return null;
  }
  return parsed;
}

int? _amount(Map<String, dynamic> args, String key, List<String> errors) {
  if (!args.containsKey(key)) return null;
  final value = args[key];
  final minor = value is bool
      ? null
      : value is num && value.isFinite
      ? _parseExactBaht(value.toString())
      : value is String
      ? _parseExactBaht(value)
      : null;
  if (minor != null) {
    try {
      _bahtNumber(minor);
    } on RangeError {
      errors.add('$key cannot be represented exactly as a tool number.');
      return null;
    }
  } else {
    errors.add(
      '$key must be a nonnegative THB amount with at most two decimals.',
    );
  }
  return minor;
}

const int _maxInt64Minor = 9223372036854775807;

/// Parse decimal baht with BigInt intermediates so even hostile tool output
/// cannot overflow while converting to 64-bit satang.
int? _parseExactBaht(String text) {
  final match = RegExp(r'^(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?$')
      .firstMatch(text.trim());
  if (match == null) return null;
  final whole = BigInt.tryParse(match[1]!.replaceAll(',', ''));
  if (whole == null) return null;
  final fraction = (match[2] ?? '').padRight(2, '0');
  final minor = whole * BigInt.from(100) + BigInt.parse(fraction);
  if (minor > BigInt.from(_maxInt64Minor)) return null;
  return minor.toInt();
}

bool? _boolean(Map<String, dynamic> args, String key, List<String> errors) {
  if (!args.containsKey(key)) return null;
  final value = args[key];
  if (value is bool) return value;
  errors.add('$key must be true or false.');
  return null;
}

List<String> _stringList(
  Map<String, dynamic> args,
  String key,
  List<String> errors,
) {
  if (!args.containsKey(key)) return const [];
  final value = args[key];
  if (value is List && value.every((e) => e is String)) {
    return value.cast<String>();
  }
  errors.add('$key must be a list of text.');
  return const [];
}

Set<Category> _categories(
  Map<String, dynamic> args,
  String key,
  List<String> errors,
) {
  final result = <Category>{};
  for (final raw in _stringList(args, key, errors)) {
    final category = Category.tryParse(raw);
    if (category == null) {
      errors.add('Unknown category "$raw".');
    } else {
      result.add(category);
    }
  }
  return result;
}
