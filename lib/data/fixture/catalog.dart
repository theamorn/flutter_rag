import '../../core/categories.dart';

/// A merchant the generator can draw. Amounts are whole-baht ranges;
/// [satang] adds .00/.25/.50/.75 for shops where odd totals are normal.
class MerchantSpec {
  const MerchantSpec(
    this.name,
    this.category,
    this.minBaht,
    this.maxBaht, {
    this.weight = 1,
    this.satang = false,
    this.minHour = 7,
    this.maxHour = 22,
  });

  final String name;
  final Category category;
  final int minBaht;
  final int maxBaht;
  final double weight;
  final bool satang;
  final int minHour;
  final int maxHour;
}

/// The four scheduled shops (exact display names from the spec).
const MerchantSpec kSevenElevenSpec = MerchantSpec(
    '7-11', Category.grocery, 35, 450, satang: true, minHour: 6, maxHour: 23);
const MerchantSpec kSushiroSpec =
    MerchantSpec('Sushiro', Category.food, 280, 1450, minHour: 11, maxHour: 21);
const MerchantSpec kTermsGamesSpec =
    MerchantSpec('TermsGames', Category.entertainment, 100, 1000);
const MerchantSpec kUniqloSpec = MerchantSpec(
    'Uniqlo', Category.clothing, 390, 3990, minHour: 10, maxHour: 21);

/// TermsGames top-ups come in fixed denominations (baht).
const List<int> kTermsGamesDenominations = [100, 150, 200, 300, 500, 1000];

/// Monthly bills: one of each per calendar month, on days 20-28.
const List<MerchantSpec> kMonthlyBills = [
  MerchantSpec('City Electric', Category.utility, 900, 3200, minHour: 8, maxHour: 20),
  MerchantSpec('Water Works', Category.utility, 150, 450, minHour: 8, maxHour: 20),
  MerchantSpec('FiberNet', Category.utility, 599, 899, minHour: 8, maxHour: 20),
  MerchantSpec('MobileOne', Category.utility, 399, 799, minHour: 8, maxHour: 20),
  MerchantSpec('Sunrise Condo Office', Category.bill, 2500, 2500,
      minHour: 9, maxHour: 17),
];

/// Unrestricted filler. Must never contain the four scheduled shops or an
/// authored-only shop (authored_catalog_test.dart checks this).
const List<MerchantSpec> kFillerMerchants = [
  // food
  MerchantSpec('Night Noodle', Category.food, 60, 220, weight: 6, minHour: 17, maxHour: 23),
  MerchantSpec('Kopi Corner', Category.food, 55, 180, weight: 5, minHour: 7, maxHour: 17),
  MerchantSpec('Baan Som Tam', Category.food, 80, 350, weight: 4, minHour: 11, maxHour: 21),
  MerchantSpec('Rice Bowl Express', Category.food, 70, 250, weight: 4, minHour: 10, maxHour: 21),
  MerchantSpec('Golden Wok', Category.food, 120, 600, weight: 3, minHour: 11, maxHour: 22),
  MerchantSpec('Pizza Hub', Category.food, 250, 900, weight: 2, minHour: 11, maxHour: 22),
  MerchantSpec('Seoul Grill', Category.food, 400, 1600, weight: 1, minHour: 17, maxHour: 22),
  // grocery
  MerchantSpec('Big Mart', Category.grocery, 80, 1800, weight: 4, satang: true),
  MerchantSpec('Green Basket', Category.grocery, 100, 2500, weight: 3, satang: true),
  MerchantSpec('Fresh Market', Category.grocery, 40, 600, weight: 2, satang: true, minHour: 6, maxHour: 14),
  // travel
  MerchantSpec('City Taxi', Category.travel, 80, 450, weight: 3),
  MerchantSpec('SkyRail Card', Category.travel, 100, 500, weight: 3, minHour: 6, maxHour: 21),
  MerchantSpec('Coach Express', Category.travel, 250, 900, weight: 1),
  MerchantSpec('Siam Air', Category.travel, 1500, 6500, weight: 0.3),
  MerchantSpec('Riverside Hotel', Category.travel, 1200, 4500, weight: 0.3),
  // entertainment
  MerchantSpec('Screen City Cinema', Category.entertainment, 180, 600, weight: 1.5, minHour: 12, maxHour: 22),
  MerchantSpec('StreamBox', Category.entertainment, 149, 419, weight: 0.5),
  MerchantSpec('Bowling Hub', Category.entertainment, 200, 800, weight: 0.5, minHour: 14, maxHour: 22),
  MerchantSpec('Riverside Events', Category.entertainment, 500, 3500, weight: 0.3),
  // personal care
  MerchantSpec('Siam Pharmacy', Category.personalCare, 60, 1200, weight: 2, satang: true),
  MerchantSpec('Cut & Style Salon', Category.personalCare, 250, 1500, weight: 0.7, minHour: 10, maxHour: 20),
  MerchantSpec('FitLife Gym', Category.personalCare, 1299, 1299, weight: 0.3),
  // clothing
  MerchantSpec('Shoe Lab', Category.clothing, 900, 4500, weight: 0.4, minHour: 10, maxHour: 21),
  MerchantSpec('Denim District', Category.clothing, 590, 2900, weight: 0.4, minHour: 10, maxHour: 21),
  // bill
  MerchantSpec('SafeLife Insurance', Category.bill, 1500, 4500, weight: 0.1),
  MerchantSpec('Lingo Language School', Category.bill, 2000, 8000, weight: 0.05),
  // utility
  MerchantSpec('MobileOne', Category.utility, 100, 500, weight: 0.3),
];

/// Friends: occasional transfer recipients outside the family group.
const List<String> kFriends = ['Alex', 'Ploy', 'Nok', 'Ben'];

/// Memo templates by category for generated (non-authored) rows. `{friend}`
/// becomes a friend's name. None may contain a [kReservedMemoTerms] entry,
/// so only authored rows answer the semantic evaluation queries.
const Map<Category, List<String>> kMemoTemplates = {
  Category.food: [
    'Team lunch after the quarterly review',
    'Birthday dinner for {friend}',
    'Lunch with old classmates',
    'Celebration dinner after the promotion',
    'Treated my cousin to dinner',
    'Dinner with clients from Singapore',
  ],
  Category.grocery: [
    'Weekly groceries for the family',
    'Ingredients for the cooking class',
    'Snacks for the office party',
    'Bulk rice and cooking oil',
  ],
  Category.travel: [
    'Flight to Phuket for the conference',
    'Taxi back after the late shift',
    'Hotel night in Hua Hin for the wedding',
    'Bus ticket to Chiang Rai',
  ],
  Category.entertainment: [
    'Concert tickets with {friend}',
    'Bowling night with the team',
    'Yearly streaming subscription',
    'Football match tickets',
  ],
  Category.personalCare: [
    'Prescription refill',
    'Haircut before the wedding',
    'Gym membership renewal',
    'Dental cleaning co-pay',
  ],
  Category.clothing: [
    'Work shirts for the new job',
    'Running shoes for the marathon',
    'Wedding outfit',
    'Winter jacket for the Japan visit',
  ],
  Category.bill: [
    'Car insurance renewal',
    'Language course for the year',
    'Credit card annual fee',
  ],
  Category.utility: [
    'Paid the phone bill early before travelling',
    'Internet upgrade to fibre',
    'Water bill with the overdue fee',
  ],
};

const List<String> kTermsGamesMemos = [
  'Top-up for the new season pass',
  'Bought gems for the anniversary event',
];

const Map<String, List<String>> kFamilyMemoTemplates = {
  'Mom': ['Monthly support for Mom', 'Birthday gift money for Mom'],
  'Dad': ['Monthly bill support for Dad', "Dad's birthday gift money"],
  'Kids': ['Weekly allowance for the kids', 'Lunch money for the kids'],
  'Amorn': ['Paid Amorn back for concert tickets', 'Shared groceries paid to Amorn'],
};

/// Friend-transfer memos by the transfer's category.
const Map<Category, List<String>> kFriendMemoTemplates = {
  Category.food: ['Paid {friend} back for lunch', 'Paid {friend} back for coffee'],
  Category.travel: ['Split the taxi with {friend}', 'Paid {friend} back for bus tickets'],
  Category.entertainment: [
    'Paid {friend} back for concert tickets',
    'Paid {friend} back for movie tickets',
  ],
};

/// Lower-case fragments reserved for authored rows. A generated memo with one
/// would be an unlabelled answer to a semantic evaluation query.
const List<String> kReservedMemoTerms = [
  'camp', 'tent', 'sleeping', 'headlamp', 'lantern', 'firewood',
  'hiking', 'stove', 'repellent', 'backpack', 'outdoor',
  'house', 'home', 'rent', 'repair', 'apartment', 'deposit',
  'school', 'fees', 'tuition', 'electricity',
  'group trip', 'leap', 'countdown', 'new year',
];
