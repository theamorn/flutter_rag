import '../../core/bangkok_time.dart';
import '../../core/categories.dart';
import '../../core/transaction.dart';

/// Hand-written rows with known answers (spec §6.1). They are part of every
/// fixture size and keep their IDs, so the evaluation set can name them.
/// Times are Bangkok wall-clock.
///
/// Windows the presentation depends on:
/// - Step 2: camping purchases, Sep 2026, < THB 3,000, not food -> a01 a02 a03
/// - Step 4: the same filters in Aug-Sep 2025 -> a07 a08 a09
final List<Transaction> kAuthoredTransactions = [
  // --- Camping, September 2026 (step 2) and its distractors ---
  _shop('txn_a01', 2026, 9, 12, 14, 20, 'Trail Supply', Category.travel, 129900,
      'Card payment at Trail Supply',
      'Sleeping bag and headlamp for our weekend camping trip'),
  _shop('txn_a02', 2026, 9, 14, 18, 5, 'Outdoor Base', Category.travel, 245000,
      'Card payment at Outdoor Base',
      'Two-person tent for the Khao Yai camping weekend'),
  _shop('txn_a03', 2026, 9, 16, 19, 30, 'Big Mart', Category.grocery, 64000,
      'QR payment to Big Mart', 'Insect repellent and a lantern for camping'),
  _shop('txn_a04', 2026, 9, 17, 20, 10, 'Camp Grill House', Category.food, 82000,
      'Card payment at Camp Grill House',
      'Dinner at the campsite restaurant after setting up the tent'),
  _shop('txn_a05', 2026, 9, 10, 11, 45, 'Trail Supply', Category.travel, 489000,
      'Card payment at Trail Supply', 'Hiking backpack for the camping trip'),
  _shop('txn_a06', 2026, 8, 29, 16, 0, 'Outdoor Base', Category.travel, 115000,
      'Card payment at Outdoor Base', 'Camping chairs for the trip'),
  // --- Camping, August-September 2025 (step 4 follow-up) and distractors ---
  _shop('txn_a07', 2025, 8, 23, 13, 15, 'Trail Supply', Category.travel, 189000,
      'Card payment at Trail Supply',
      'Sleeping pads for the Doi Inthanon camping trip'),
  _shop('txn_a08', 2025, 9, 6, 10, 30, 'Outdoor Base', Category.travel, 98000,
      'Card payment at Outdoor Base', 'Camping stove gas canisters'),
  _shop('txn_a09', 2025, 9, 20, 17, 40, 'Big Mart', Category.grocery, 45000,
      'QR payment to Big Mart', 'Firewood and matches for camping'),
  _shop('txn_a10', 2025, 7, 30, 15, 20, 'Outdoor Base', Category.travel, 120000,
      'Card payment at Outdoor Base', 'Rain cover for the tent'),
  _shop('txn_a11', 2025, 9, 7, 8, 15, 'Camp Grill House', Category.food, 56000,
      'Card payment at Camp Grill House', 'Breakfast at the campground cafe'),
  // --- Calendar edge cases ---
  _shop('txn_a12', 2024, 2, 29, 20, 30, 'Screen City Cinema',
      Category.entertainment, 52000, 'Card payment at Screen City Cinema',
      'Leap day movie night'),
  // 23:40 on 31 Aug (Bangkok) is August. 00:20 on 1 Sep (Bangkok) is
  // September in Bangkok but still 31 Aug in UTC.
  _shop('txn_a13', 2026, 8, 31, 23, 40, 'Night Noodle', Category.food, 18000,
      'QR payment to Night Noodle', null),
  _shop('txn_a14', 2026, 9, 1, 0, 20, 'Night Noodle', Category.food, 16000,
      'QR payment to Night Noodle', null),
  _shop('txn_a15', 2025, 12, 31, 23, 50, 'Riverside Events',
      Category.entertainment, 150000, 'Card payment at Riverside Events',
      "New Year's Eve countdown tickets"),
  _shop('txn_a16', 2026, 1, 1, 0, 10, 'Night Noodle', Category.food, 22000,
      'QR payment to Night Noodle', null),
  // Equal amounts on different dates (and equal to a01).
  _shop('txn_a17', 2025, 3, 5, 18, 0, 'FitLife Gym', Category.personalCare,
      129900, 'Card payment at FitLife Gym', null),
  _shop('txn_a18', 2026, 3, 5, 18, 0, 'FitLife Gym', Category.personalCare,
      129900, 'Card payment at FitLife Gym', null),
  // Same day, payee, amount and time, no memo, no description: only the
  // "Ref <id>" suffix keeps their retrieval documents distinct.
  _shop('txn_a19', 2026, 6, 15, 12, 0, 'Big Mart', Category.grocery, 25000,
      null, null),
  _shop('txn_a20', 2026, 6, 15, 12, 0, 'Big Mart', Category.grocery, 25000,
      null, null),
  // --- People ---
  _person('txn_a21', 2026, 7, 19, 21, 0, 'Alex', Category.food, 65000,
      'PromptPay transfer to Alex', 'Paid Alex back for dinner on our group trip'),
  _person('txn_a22', 2026, 5, 8, 9, 0, 'Amorn', Category.bill, 650000,
      'PromptPay transfer to Amorn', 'My share of the house repair paid to Amorn'),
  _person('txn_a23', 2025, 11, 3, 8, 30, 'Dad', Category.utility, 230000,
      'PromptPay transfer to Dad',
      'Helping Dad pay the electricity bill this month'),
  _person('txn_a24', 2026, 9, 2, 7, 45, 'Mom', Category.bill, 1000000,
      'PromptPay transfer to Mom',
      'My share of September rent for the family home'),
  _person('txn_a25', 2026, 1, 12, 10, 0, 'Kids', Category.bill, 1500000,
      'PromptPay transfer to Kids', 'School fees for the new term'),
  _person('txn_a26', 2026, 2, 20, 19, 0, 'Ploy', Category.bill, 300000,
      'PromptPay transfer to Ploy', 'Helping Ploy with her house deposit'),
  _person('txn_a27', 2024, 6, 1, 10, 0, 'Khun Somchai', Category.bill, 3000000,
      'Bank transfer', 'Deposit for the new apartment'),
  // --- Unknowable purpose, memo edits, the oldest year ---
  _shop('txn_a28', 2026, 9, 18, 15, 10, 'Outdoor Base', Category.travel, 160000,
      'Card payment at Outdoor Base', null),
  _shop('txn_a29', 2026, 4, 10, 16, 20, 'Big Mart', Category.grocery, 89000,
      'QR payment to Big Mart', 'Groceries for the housewarming party'),
  _shop('txn_a30', 2023, 11, 25, 11, 0, 'Trail Supply', Category.travel, 210000,
      'Card payment at Trail Supply',
      'Headlamp and tent pegs for my first camping trip'),
];

/// Shops that only authored rows use. Filler never draws them, so
/// camping-flavoured merchants appear only where the evaluation expects them.
const Set<String> kAuthoredOnlyShops = {
  'Trail Supply',
  'Outdoor Base',
  'Camp Grill House',
};

Transaction _shop(String id, int y, int mo, int d, int h, int mi, String shop,
        Category category, int amountMinor, String? description, String? memo) =>
    Transaction(
      id: id,
      occurredAt: bangkokToUtc(y, mo, d, h, mi),
      shopName: shop,
      type: TransactionType.purchase,
      amountMinor: amountMinor,
      category: category,
      description: description,
      memo: memo,
    );

Transaction _person(String id, int y, int mo, int d, int h, int mi,
        String person, Category category, int amountMinor, String? description,
        String? memo) =>
    Transaction(
      id: id,
      occurredAt: bangkokToUtc(y, mo, d, h, mi),
      personName: person,
      type: TransactionType.transfer,
      amountMinor: amountMinor,
      category: category,
      description: description,
      memo: memo,
    );
