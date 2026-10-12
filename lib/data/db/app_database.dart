import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Drift in raw-SQL mode: no generated code (project rule; see
/// docs/learning.md "Drift without build_runner"). Schema = spec §5.1.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  /// Opens or creates [file]. Queries run on a background isolate.
  factory AppDatabase.open(File file) =>
      AppDatabase(NativeDatabase.createInBackground(file));

  /// In-memory database for tests.
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          for (final statement in kSchema) {
            await customStatement(statement);
          }
        },
      );
}

const List<String> kSchema = [
  '''
CREATE TABLE transactions (
  id               TEXT PRIMARY KEY,
  occurred_at      INTEGER NOT NULL,
  shop_name        TEXT,
  person_name      TEXT,
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('purchase','transfer')),
  amount_minor     INTEGER NOT NULL CHECK (amount_minor > 0),
  currency         TEXT NOT NULL CHECK (currency = 'THB'),
  category         TEXT NOT NULL CHECK (category IN ('bill','food','travel',
                     'entertainment','utility','personal_care','grocery','clothing')),
  description      TEXT,
  memo             TEXT,
  CHECK ((shop_name IS NULL) <> (person_name IS NULL)),
  CHECK ((transaction_type = 'purchase') = (shop_name IS NOT NULL))
)''',
  'CREATE INDEX idx_txn_time ON transactions (occurred_at DESC, id DESC)',
  'CREATE INDEX idx_txn_cat_time ON transactions (category, occurred_at)',
  'CREATE INDEX idx_txn_shop ON transactions (shop_name)',
  'CREATE INDEX idx_txn_person ON transactions (person_name)',
  '''
CREATE TABLE rag_sources (
  txn_id    TEXT PRIMARY KEY REFERENCES transactions(id),
  source_id INTEGER NOT NULL UNIQUE,
  doc_text  TEXT NOT NULL,
  vector    BLOB NOT NULL
)''',
  'CREATE TABLE app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
];
