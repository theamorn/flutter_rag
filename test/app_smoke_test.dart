import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_rag/app.dart';
import 'package:flutter_rag/app_services.dart';
import 'package:flutter_rag/data/db/app_database.dart';
import 'package:flutter_rag/ui/transaction_tile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('boots, seeds, and lists the newest transactions', (tester) async {
    late AppServices services;
    await tester.runAsync(() async {
      services = await AppServices.open(AppDatabase.memory(), 300);
      await services.search.browse();
    });
    await tester.pumpWidget(TransactionSearchApp(services: services));
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Demo date: 3 Oct 2026'), findsOneWidget);
    expect(find.text('300 transactions'), findsOneWidget);
    expect(find.byType(TransactionTile), findsWidgets);
    await tester.runAsync(services.dispose);
  });
}
