import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../core/categories.dart';
import '../../core/transaction.dart';
import '../../search/search_plan.dart';
import '../../search/search_sql.dart';
import 'app_database.dart';

class ExactSummary {
  const ExactSummary(this.count, this.totalMinor);

  final int count;
  final int totalMinor;
}

/// Reads and writes the authoritative transaction table.
class TransactionRepository {
  TransactionRepository(this.db);

  final AppDatabase db;

  static const String _columns = 'id, occurred_at, shop_name, person_name, '
      'transaction_type, amount_minor, currency, category, description, memo';

  Future<int> count() async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS n FROM transactions')
        .getSingle();
    return row.read<int>('n');
  }

  Future<void> insertAll(Iterable<Transaction> rows) => db.batch((b) {
        for (final t in rows) {
          b.customStatement(
            'INSERT INTO transactions ($_columns) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              t.id,
              t.occurredAt.millisecondsSinceEpoch,
              t.shopName,
              t.personName,
              t.type.name,
              t.amountMinor,
              t.currency,
              t.category.dbValue,
              t.description,
              t.memo,
            ],
          );
        }
      });

  Future<Transaction?> getById(String id) async {
    final rows =
        await _select('SELECT $_columns FROM transactions WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  /// Rows for [ids] in the given order. Unknown ids are skipped.
  Future<List<Transaction>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _select(
        'SELECT $_columns FROM transactions WHERE id IN (${sqlMarks(ids.length)})',
        ids);
    final byId = {for (final t in rows) t.id: t};
    return [for (final id in ids) ?byId[id]];
  }

  Future<List<Transaction>> all() => _select(
      'SELECT $_columns FROM transactions ORDER BY occurred_at DESC, id DESC',
      const []);

  /// One page of the plan's rows in the plan's order, honouring
  /// [SearchPlan.limit] across pages.
  Future<List<Transaction>> page(SearchPlan plan,
      {required int offset, required int limit}) async {
    var take = limit;
    final cap = plan.limit;
    if (cap != null) {
      take = math.min(limit, cap - offset);
      if (take <= 0) return const [];
    }
    final f = sqlFilterFor(plan);
    return _select(
      'SELECT $_columns FROM transactions WHERE ${f.where} '
      'ORDER BY ${sqlOrderFor(plan.sort)} LIMIT ? OFFSET ?',
      [...f.args, take, offset],
    );
  }

  /// Count and total of every row the plan selects (after its limit).
  Future<ExactSummary> summarize(SearchPlan plan) async {
    final f = sqlFilterFor(plan);
    final limit = plan.limit;
    final inner = limit == null
        ? 'SELECT amount_minor FROM transactions WHERE ${f.where}'
        : 'SELECT amount_minor FROM transactions WHERE ${f.where} '
            'ORDER BY ${sqlOrderFor(plan.sort)} LIMIT $limit';
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS n, COALESCE(SUM(amount_minor), 0) AS total FROM ($inner)',
          variables: sqlVars(f.args),
        )
        .getSingle();
    return ExactSummary(row.read<int>('n'), row.read<int>('total'));
  }

  Future<int> sumAmounts(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount_minor), 0) AS total FROM transactions '
          'WHERE id IN (${sqlMarks(ids.length)})',
          variables: sqlVars(ids),
        )
        .getSingle();
    return row.read<int>('total');
  }

  /// Saves [memo]; blank text is stored as null. Returns the updated row.
  Future<Transaction> updateMemo(String id, String? memo) async {
    final changed = await db.customUpdate(
      'UPDATE transactions SET memo = ? WHERE id = ?',
      variables: sqlVars([normalizeMemo(memo), id]),
    );
    if (changed != 1) throw StateError('No transaction $id');
    return (await getById(id))!;
  }

  Future<List<String>> distinctShopNames() => _names('shop_name');
  Future<List<String>> distinctPersonNames() => _names('person_name');

  Future<List<String>> _names(String column) async {
    final rows = await db
        .customSelect('SELECT DISTINCT $column AS name FROM transactions '
            'WHERE $column IS NOT NULL ORDER BY $column')
        .get();
    return [for (final r in rows) r.read<String>('name')];
  }

  Future<List<Transaction>> _select(String sql, List<Object?> args) async {
    final rows = await db.customSelect(sql, variables: sqlVars(args)).get();
    return [for (final r in rows) _fromRow(r)];
  }

  static Transaction _fromRow(QueryRow r) => Transaction(
        id: r.read<String>('id'),
        occurredAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('occurred_at'),
            isUtc: true),
        shopName: r.readNullable<String>('shop_name'),
        personName: r.readNullable<String>('person_name'),
        type: TransactionType.fromDb(r.read<String>('transaction_type')),
        amountMinor: r.read<int>('amount_minor'),
        currency: r.read<String>('currency'),
        category: Category.fromDb(r.read<String>('category')),
        description: r.readNullable<String>('description'),
        memo: r.readNullable<String>('memo'),
      );
}
