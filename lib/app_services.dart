import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

import 'advanced/advanced_controller.dart';
import 'advanced/flutter_gemma_installer.dart';
import 'advanced/flutter_gemma_runtime.dart';
import 'advanced/gemma_installer.dart';
import 'advanced/gemma_runtime.dart';
import 'core/payees.dart';
import 'data/db/app_database.dart';
import 'data/db/rag_source_store.dart';
import 'data/db/seed.dart';
import 'data/db/transaction_repository.dart';
import 'perf/timing_log.dart';
import 'results/search_controller.dart';
import 'results/search_engine.dart';
import 'retrieval/index_manager.dart';
import 'retrieval/rag_index.dart';
import 'retrieval/semantic_retriever.dart';
import 'search/entities.dart';
import 'search/mlkit_entity_source.dart';
import 'search/plan_validator.dart';
import 'search/rules/rule_parser.dart';
import 'search/rules/rule_refiner.dart';
import 'search/standard_interpreter.dart';

/// Fixture size for this build: `--dart-define=FIXTURE_SIZE=300|3000|5500`.
const int kFixtureSize = int.fromEnvironment(
  'FIXTURE_SIZE',
  defaultValue: 5500,
);

/// Owns every long-lived service. The one place to swap in fakes.
class AppServices {
  AppServices._({
    required this.db,
    required this.repo,
    required this.store,
    required this.directory,
    required this.fixtureSize,
    required this.entities,
    required this.ragIndex,
    required this.index,
    required this.search,
    required this.advanced,
    required this.timingLog,
    required this.dbPaths,
  });

  final AppDatabase db;
  final TransactionRepository repo;
  final RagSourceStore store;
  final PayeeDirectory directory;
  final int fixtureSize;
  final EntitySource entities;

  /// Null when running without a retrieval engine (exact search only).
  final RagIndex? ragIndex;
  final IndexManager? index;
  final TransactionSearchController search;
  final AdvancedController? advanced;
  final TimingLog timingLog;
  final List<String> dbPaths;

  static Future<AppServices> open(
    AppDatabase db,
    int fixtureSize, {
    EntitySource entities = const NoEntitySource(),
    RagIndex? rag,
    GemmaInstaller? installer,
    GemmaRuntime? runtime,
    RetrievalConfig retrievalConfig = kRetrievalConfig,
    List<String> dbPaths = const [],
    bool useAdvancedPlanner = true,
  }) async {
    final repo = TransactionRepository(db);
    await seedIfEmpty(db, repo, fixtureSize);
    final directory = PayeeDirectory(
      shops: await repo.distinctShopNames(),
      people: await repo.distinctPersonNames(),
    );
    final store = RagSourceStore(db);
    final index = rag == null
        ? null
        : IndexManager(repo: repo, store: store, rag: rag);
    final parser = RuleParser(directory: directory);
    final advanced = installer == null || runtime == null
        ? null
        : AdvancedController(
            installer: installer,
            runtime: runtime,
            directory: directory,
          );
    final timingLog = TimingLog();
    final search = TransactionSearchController(
      onTiming: timingLog.add,
      advanced: advanced,
      useAdvancedPlanner: useAdvancedPlanner,
      repo: repo,
      engine: SearchEngine(
        repo: repo,
        retriever: rag == null
            ? null
            : SemanticRetriever(
                repo: repo,
                store: store,
                rag: rag,
                config: retrievalConfig,
              ),
      ),
      validator: PlanValidator(directory),
      interpreter: StandardInterpreter(entities: entities, parser: parser),
      refiner: RuleRefiner(parser),
      onMemoChanged: index?.refreshTransaction,
    );
    return AppServices._(
      db: db,
      repo: repo,
      store: store,
      directory: directory,
      fixtureSize: fixtureSize,
      entities: entities,
      ragIndex: rag,
      index: index,
      search: search,
      timingLog: timingLog,
      dbPaths: dbPaths,
      advanced: advanced,
    );
  }

  /// Production boot: one transaction DB and one engine DB per fixture size;
  /// indexing starts in the background (searches work meanwhile).
  static Future<AppServices> boot() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/txn_$kFixtureSize.sqlite');
    final rag = await MobileRagIndex.open(fixtureSize: kFixtureSize);
    final services = await open(
      AppDatabase.open(file),
      kFixtureSize,
      entities: MlKitEntitySource(),
      rag: rag,
      installer: FlutterGemmaInstaller(),
      runtime: FlutterGemmaRuntime(),
      useAdvancedPlanner: false,
      dbPaths: [
        file.path,
        '${file.path}-wal',
        MobileRag.instance.dbPath,
        '${MobileRag.instance.dbPath}-wal',
        '${dir.path}/rag_${kFixtureSize}_hnsw.hnsw.data',
        '${dir.path}/rag_${kFixtureSize}_hnsw.hnsw.graph',
      ],
    );
    unawaited(services.index!.ensureIndexed().catchError((Object _) {}));
    return services;
  }

  Future<void> dispose() async {
    await advanced?.disable();
    search.dispose();
    timingLog.dispose();
    advanced?.dispose();
    await entities.close();
    await db.close();
  }
}
