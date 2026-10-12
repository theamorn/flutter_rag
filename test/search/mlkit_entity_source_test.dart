import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rag/search/mlkit_entity_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_mlkit_entity_extractor');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('iOS setup completes when the model-manager callback is lost', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var ready = false;
    String? opened;
    String? closed;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      if (call.method == 'nlp#manageEntityExtractionModels') {
        if (args['task'] == 'check') return ready;
        // The pinned iOS manager downloads the model but loses the callback.
        return Completer<Object?>().future;
      }
      if (call.method == 'nlp#startEntityExtractor') {
        expect(args['language'], 'english');
        opened = args['id'] as String;
        ready = true;
        return <Object>[];
      }
      if (call.method == 'nlp#closeEntityExtractor') {
        closed = args['id'] as String;
        return null;
      }
      throw StateError('Unexpected call: ${call.method}');
    });

    final finished = await Future.any([
      MlKitEntitySource.downloadModel(),
      Future<bool>.delayed(const Duration(seconds: 1), () => false),
    ]);
    expect(finished, isTrue);
    expect(opened, isNotNull);
    expect(closed, opened, reason: 'The setup extractor must be released');
  });

  test('iOS setup closes its extractor when native download fails', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    String? opened;
    String? closed;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      if (call.method == 'nlp#manageEntityExtractionModels') {
        if (args['task'] == 'check') return false;
        return 'error';
      }
      if (call.method == 'nlp#startEntityExtractor') {
        opened = args['id'] as String;
        throw PlatformException(code: 'download_failed');
      }
      if (call.method == 'nlp#closeEntityExtractor') {
        closed = args['id'] as String;
        return null;
      }
      throw StateError('Unexpected call: ${call.method}');
    });

    await expectLater(
      MlKitEntitySource.downloadModel(),
      throwsA(isA<PlatformException>()),
    );
    expect(opened, isNotNull);
    expect(closed, opened);
  });

  test('Android setup retains the native model-manager download', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'nlp#manageEntityExtractionModels');
      expect(call.arguments, {
        'task': 'download',
        'model': 'english',
        'wifi': false,
      });
      return 'success';
    });

    expect(await MlKitEntitySource.downloadModel(), isTrue);
  });
}
