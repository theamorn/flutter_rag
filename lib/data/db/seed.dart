import 'dart:isolate';

import '../fixture/fixture_generator.dart';
import 'app_database.dart';
import 'transaction_repository.dart';

/// Inserts the [size] fixture into an empty database. Returns false when the
/// table already has rows (later launches). Generation runs off the UI isolate.
Future<bool> seedIfEmpty(
    AppDatabase db, TransactionRepository repo, int size) async {
  if (await repo.count() > 0) return false;
  final rows = await Isolate.run(() => buildFixture(size));
  await repo.insertAll(rows);
  await db.customStatement(
    'INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?), (?, ?)',
    ['fixture_size', '$size', 'fixture_seed', '$kFixtureSeed'],
  );
  return true;
}
