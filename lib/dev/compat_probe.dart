import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

import '../search/mlkit_entity_source.dart';

/// One named device check. Probes never throw: a failure becomes a failed
/// check, so one run reports everything (important in release builds).
class ProbeCheck {
  ProbeCheck(this.name, this.passed, this.detail);

  final String name;
  final bool passed;
  final String detail;

  String toLine() => '${passed ? 'PASS' : 'FAIL'} $name: $detail';
}

class ProbeRunner {
  ProbeRunner(this.tag);

  final String tag;
  final List<ProbeCheck> checks = [];

  Future<void> check(String name, Future<String> Function() body) async {
    ProbeCheck result;
    try {
      result = ProbeCheck(name, true, await body());
    } catch (e) {
      result = ProbeCheck(name, false, '$e');
    }
    checks.add(result);
    debugPrint('$tag ${result.toLine()}');
  }
}

class _ProbeDb extends GeneratedDatabase {
  _ProbeDb(super.executor);

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  int get schemaVersion => 1;
}

// 2026-10-03 12:00 Bangkok. Literal here so the probe has no app deps.
final int _referenceMs = DateTime.utc(2026, 10, 3, 5).millisecondsSinceEpoch;

String _describe(List<EntityAnnotation> annotations) => annotations
    .expand((a) => a.entities.map((e) => switch (e) {
          DateTimeEntity d =>
            '"${a.text}"[${a.start},${a.end}) date ${d.dateTimeGranularity.name} '
                '${DateTime.fromMillisecondsSinceEpoch(d.timestamp, isUtc: true).toIso8601String()}',
          MoneyEntity m =>
            '"${a.text}"[${a.start},${a.end}) money ${m.integerPart}.${m.fractionPart} '
                '"${m.unnormalizedCurrency}"',
          _ => '"${a.text}" ${e.type.name}',
        }))
    .join(' | ');

Future<List<ProbeCheck>> runStandardStackProbe() async {
  final probe = ProbeRunner('COMPAT_PROBE');

  await probe.check('sqlite_via_drift', () async {
    final db = _ProbeDb(NativeDatabase.memory());
    final row =
        await db.customSelect('SELECT sqlite_version() AS v').getSingle();
    await db.close();
    return 'sqlite ${row.read<String>('v')}';
  });

  const model = 'english'; // EntityExtractorLanguage.english.name
  await probe.check('mlkit_model', () async {
    final manager = EntityExtractorModelManager();
    final before = await manager.isModelDownloaded(model);
    if (!before) await MlKitEntitySource.downloadModel();
    final after = await manager.isModelDownloaded(model);
    if (!after) throw StateError('model still missing after download');
    return 'downloaded before=$before after=$after';
  });

  final extractor = EntityExtractor(language: EntityExtractorLanguage.english);
  Future<List<EntityAnnotation>> annotate(String text) => extractor.annotateText(
        text,
        referenceTime: _referenceMs,
        referenceTimeZone: 'GMT+7',
        preferredLocale: 'en',
        entityTypesFilter: const [EntityType.dateTime, EntityType.money],
      );

  await probe.check('mlkit_annotate', () async {
    final a = await annotate(
        'Find things I bought for camping last month, under THB 3,000, excluding food.');
    if (!a.any((x) => x.entities.any((e) => e is MoneyEntity))) {
      throw StateError('no money entity: ${_describe(a)}');
    }
    return _describe(a);
  });
  await probe.check('mlkit_7_11', () async {
    // Review Focus 2: does ML Kit read "7-11" as a date? Record either way.
    return _describe(await annotate('Show my 7-11 payments last month'));
  });
  await probe.check('mlkit_fraction', () async {
    final a = await annotate('under 3,000.5 baht');
    final b = await annotate('under 3,000.50 baht');
    return '.5 -> ${_describe(a)} ; .50 -> ${_describe(b)}';
  });
  await extractor.close();

  await probe.check('rag_init', () async {
    await MobileRag.initialize(
      tokenizerAsset: 'assets/models/minilm/tokenizer.json',
      modelAsset: 'assets/models/minilm/model.onnx',
      databaseName: 'rag_probe.sqlite',
      threadLevel: ThreadUseLevel.medium,
    );
    await MobileRag.instance.clearAllData();
    return 'db ${MobileRag.instance.dbPath}';
  });

  await probe.check('embedding_dim', () async {
    final v = await EmbeddingService.embed('sleeping bag for camping');
    if (v.length != 384) throw StateError('dim ${v.length}');
    return 'dim 384 (MobileRag.initialize also initialised EmbeddingService)';
  });

  const camping = 'Memo: Sleeping bag and headlamp for our weekend camping trip. '
      'Purchase at Trail Supply. Category: Travel. Date: 12 Sep 2026. '
      'Amount: THB 1,299.00. Ref probe_1';
  const twinA = 'Purchase at Big Mart. Category: Grocery. Date: 15 Jun 2026. '
      'Amount: THB 250.00. Ref probe_2';
  const twinB = 'Purchase at Big Mart. Category: Grocery. Date: 15 Jun 2026. '
      'Amount: THB 250.00. Ref probe_3';
  final ids = <String, int>{};

  await probe.check('add_documents', () async {
    for (final (name, text) in [
      ('probe_1', camping),
      ('probe_2', twinA),
      ('probe_3', twinB),
    ]) {
      final r = await MobileRag.instance.addDocument(text, name: name);
      final chunks = await MobileRag.instance.getSourceChunkCount(r.sourceId);
      if (r.isDuplicate || r.chunkCount != 1 || chunks != 1) {
        throw StateError('$name dup=${r.isDuplicate} chunks=${r.chunkCount}/$chunks');
      }
      ids[name] = r.sourceId;
    }
    return 'sourceIds $ids, 1 chunk each';
  });

  await probe.check('duplicate_text', () async {
    final r = await MobileRag.instance.addDocument(twinA, name: 'probe_2_dup');
    if (!(r.isDuplicate && r.chunkCount == 0 && r.sourceId == ids['probe_2'])) {
      throw StateError('dup=${r.isDuplicate} chunks=${r.chunkCount} id=${r.sourceId}');
    }
    return 'identical text -> isDuplicate, chunkCount 0, existing sourceId';
  });

  await probe.check('allowlist', () async {
    final hits = await MobileRag.instance.searchHybrid('camping',
        topK: 200, sourceIds: [ids['probe_2']!], vectorWeight: 0.5, bm25Weight: 0.5);
    if (hits.any((h) => h.sourceId != ids['probe_2'])) {
      throw StateError('hit outside allowlist: ${hits.map((h) => h.sourceId)}');
    }
    return '${hits.length} hit(s), all inside the allowlist';
  });

  await probe.check('empty_allowlist_hazard', () async {
    final hits = await MobileRag.instance.searchHybrid('camping',
        topK: 200, sourceIds: const [], vectorWeight: 0.5, bm25Weight: 0.5);
    // Expected: hits from ALL sources. This is why the app never passes [].
    return '[] returned ${hits.length} hit(s) from sources ${hits.map((h) => h.sourceId).toSet()}';
  });

  await probe.check('bm25_rank', () async {
    final hits = await MobileRag.instance
        .searchHybrid('camping', topK: 10, vectorWeight: 0.5, bm25Weight: 0.5);
    final top = hits.first;
    if (top.sourceId != ids['probe_1'] || top.bm25Rank == 0) {
      throw StateError('top=${top.sourceId} bm25Rank=${top.bm25Rank}');
    }
    final none = await MobileRag.instance
        .searchHybrid('zzqx', topK: 10, vectorWeight: 0.5, bm25Weight: 0.5);
    return 'camping top bm25Rank=${top.bm25Rank} score=${top.score}; '
        'zzqx bm25Ranks=${none.map((h) => h.bm25Rank).toList()} '
        'scores=${none.map((h) => h.score.toStringAsFixed(4)).toList()}';
  });

  await probe.check('list_sources', () async {
    final sources = await MobileRag.instance.listSources();
    final names = {for (final s in sources) s.name: s.id};
    for (final n in ['probe_1', 'probe_2', 'probe_3']) {
      if (names[n] != ids[n]) throw StateError('missing $n in $names');
    }
    return '${sources.length} sources; names round-trip';
  });

  await probe.check('remove_readd', () async {
    await MobileRag.instance.removeSource(ids['probe_1']!);
    final r = await MobileRag.instance.addDocument(camping, name: 'probe_1');
    if (r.isDuplicate || r.sourceId == ids['probe_1']) {
      throw StateError('dup=${r.isDuplicate} id=${r.sourceId}');
    }
    return 'new sourceId ${r.sourceId} (was ${ids['probe_1']})';
  });

  return probe.checks;
}
