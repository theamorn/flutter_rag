import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import 'gemma_installer.dart';
import 'gemma_model.dart';

/// Gemma 4 E2B .litertlm via flutter_gemma. FlutterGemma.initialize runs on
/// first use only, so default-off mode never touches the plugin (spec §13).
class FlutterGemmaInstaller implements GemmaInstaller {
  static Future<void>? _initialization;

  static Future<void> ensureInitialized() async {
    final pending = _initialization ??= FlutterGemma.initialize(
      inferenceEngines: [const LiteRtLmEngine()],
    );
    try {
      await pending;
    } catch (_) {
      if (identical(_initialization, pending)) _initialization = null;
      rethrow;
    }
  }

  @override
  Future<bool> isInstalled() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$kGemmaModelFile');
    return await file.exists() && await file.length() == kGemmaModelBytes;
  }

  @override
  Future<void> install({
    required void Function(int percent) onProgress,
    required GemmaCancelSignal cancel,
  }) async {
    if (cancel.isCancelled) throw const GemmaDownloadCancelled();
    await ensureInitialized();
    if (cancel.isCancelled) throw const GemmaDownloadCancelled();
    final token = CancelToken();
    cancel.onCancel(() => token.cancel('User cancelled'));
    try {
      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromNetwork(kGemmaModelUrl).withProgress(onProgress).withCancelToken(token).install();
    } on DownloadCancelledException {
      throw const GemmaDownloadCancelled();
    }
  }

  /// Re-running install() on an installed model re-activates it without a
  /// download (verified in Task 3; see learning.md if that changed).
  @override
  Future<void> activate() async {
    await ensureInitialized();
    await FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(kGemmaModelUrl).install();
  }
}
