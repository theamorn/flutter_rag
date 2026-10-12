import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';

import '../core/bangkok_time.dart';
import 'entities.dart';

/// ML Kit entity extraction (dates and money only). Reference time is the
/// fixed demo date; the zone is 'GMT+7' because the iOS plugin parses it
/// with TimeZone(abbreviation:) (learning.md).
class MlKitEntitySource implements EntitySource {
  MlKitEntitySource();

  static const String modelId = 'english';

  final EntityExtractor _extractor =
      EntityExtractor(language: EntityExtractorLanguage.english);

  static Future<bool> isModelReady() =>
      EntityExtractorModelManager().isModelDownloaded(modelId);

  /// Prepares the English model during setup. The pinned iOS model manager
  /// loses download notifications, so use the extractor's direct completion
  /// callback there (see Task 27 in learning.md).
  static Future<bool> downloadModel() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return EntityExtractorModelManager().downloadModel(
        modelId,
        isWifiRequired: false,
      );
    }
    final extractor = EntityExtractor(
      language: EntityExtractorLanguage.english,
    );
    try {
      // The iOS plugin calls downloadModelIfNeeded before annotating. A small
      // non-empty setup phrase also works when the model is already present.
      await extractor.annotateText('Ready');
      return await isModelReady();
    } finally {
      await extractor.close();
    }
  }

  @override
  Future<List<ExtractedEntity>> extract(String text) async {
    final annotations = await _extractor.annotateText(
      text,
      referenceTime: kReferenceNow.millisecondsSinceEpoch,
      referenceTimeZone: 'GMT+7',
      preferredLocale: 'en',
      entityTypesFilter: const [EntityType.dateTime, EntityType.money],
    );
    final out = <ExtractedEntity>[];
    for (final a in annotations) {
      for (final e in a.entities) {
        final converted = _convert(a, e);
        if (converted != null) out.add(converted);
      }
    }
    return out;
  }

  static ExtractedEntity? _convert(EntityAnnotation a, Entity e) => switch (e) {
        DateTimeEntity d => ExtractedDate(a.start, a.end, a.text,
            instant: DateTime.fromMillisecondsSinceEpoch(d.timestamp, isUtc: true),
            granularity: _granularity(d.dateTimeGranularity)),
        // Money is only ever noted, so the fraction's exact encoding
        // (see learning.md, Task 2) does not affect filters.
        MoneyEntity m => ExtractedMoney(a.start, a.end, a.text,
            minor: m.integerPart * 100 + m.fractionPart.clamp(0, 99),
            currency: m.unnormalizedCurrency),
        _ => null,
      };

  static DateGranularity _granularity(DateTimeGranularity g) => switch (g) {
        DateTimeGranularity.year => DateGranularity.year,
        DateTimeGranularity.month => DateGranularity.month,
        DateTimeGranularity.week => DateGranularity.week,
        DateTimeGranularity.day => DateGranularity.day,
        DateTimeGranularity.hour => DateGranularity.hour,
        DateTimeGranularity.minute => DateGranularity.minute,
        DateTimeGranularity.second => DateGranularity.second,
        DateTimeGranularity.unknown => DateGranularity.unknown,
      };

  @override
  Future<void> close() => _extractor.close();
}
