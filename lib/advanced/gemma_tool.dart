/// Host-testable declaration of the one Gemma planning tool.
class ToolSpec {
  const ToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
}

const List<String> kToolCategories = [
  'bill',
  'food',
  'travel',
  'entertainment',
  'utility',
  'personal_care',
  'grocery',
  'clothing',
];

const List<String> kClearableFields = [
  'dates',
  'amount',
  'categories',
  'payees',
  'type',
  'memo',
  'semantic',
  'sort',
  'limit',
];

const ToolSpec kSearchTool = ToolSpec(
  name: 'search_transactions',
  description:
      "Search the user's payment history. Always call this tool with every "
      'constraint in the question, including amount limits.',
  parameters: {
    'type': 'object',
    'properties': {
      'date_from': {
        'type': 'string',
        'description': 'First Bangkok calendar day, YYYY-MM-DD, inclusive',
      },
      'date_to': {
        'type': 'string',
        'description': 'Last Bangkok calendar day, YYYY-MM-DD, inclusive',
      },
      'amount_min': {
        'type': 'number',
        'description': 'Required whenever the question has a lower THB amount. Include even when dates or semantic_query are also set.',
      },
      'amount_min_inclusive': {
        'type': 'boolean',
        'description': 'true for at least; false for over (default)',
      },
      'amount_max': {
        'type': 'number',
        'description': 'Required whenever the question has an upper THB amount. Example: under THB 3,000 means amount_max: 3000.',
      },
      'amount_max_inclusive': {
        'type': 'boolean',
        'description': 'true for at most; false for under (default)',
      },
      'include_categories': {
        'type': 'array',
        'items': {'type': 'string', 'enum': kToolCategories},
      },
      'exclude_categories': {
        'type': 'array',
        'items': {'type': 'string', 'enum': kToolCategories},
      },
      'shops': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'people': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'family': {
        'type': 'boolean',
        'description': 'true means transfers to Mom, Dad, Kids, Amorn',
      },
      'transaction_type': {
        'type': 'string',
        'enum': ['purchase', 'transfer'],
      },
      'has_memo': {'type': 'boolean'},
      'semantic_query': {
        'type': 'string',
        'description': 'Purpose words only. Never put a date, amount, category or payee here.',
      },
      'sort': {
        'type': 'string',
        'enum': ['newest', 'oldest', 'amount_desc', 'amount_asc', 'relevance'],
      },
      'limit': {
        'type': 'integer',
        'description': 'Maximum row count, 1 to 200',
      },
      'clear': {
        'type': 'array',
        'items': {'type': 'string', 'enum': kClearableFields},
        'description': 'Follow-up fields to remove',
      },
    },
  },
);
