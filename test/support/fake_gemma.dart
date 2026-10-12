import 'dart:async';

import 'package:flutter_rag/advanced/gemma_installer.dart';
import 'package:flutter_rag/advanced/gemma_runtime.dart';
import 'package:flutter_rag/advanced/gemma_tool.dart';

/// Scriptable Gemma. Set [hold] to make jobs wait until the test completes
/// it (or cancel() aborts them with GemmaCancelled).
class FakeGemmaRuntime implements GemmaRuntime {
  bool loaded = false;
  bool ignoreCancel = false;
  int concurrentJobs = 0, maxConcurrentJobs = 0;
  final List<String> events = [];
  int loadCalls = 0,
      toolCalls = 0,
      generateCalls = 0,
      cancelCalls = 0,
      unloadCalls = 0;
  Map<String, dynamic> nextArgs = const {};
  String nextText = '';
  Object? nextError;
  Object? loadError;
  Completer<void>? hold;
  Completer<void>? loadHold;
  Completer<void>? cancelHold;
  String? lastSystem;
  String? lastUser;
  Completer<Object>? _inflight;

  @override
  bool get isLoaded => loaded;

  @override
  String? get backendLabel => 'fake';

  @override
  Future<void> load() async {
    loadCalls++;
    events.add('load');
    final h = loadHold;
    if (h != null) await h.future;
    final e = loadError;
    if (e != null) throw e;
    loaded = true;
  }

  @override
  Future<Map<String, dynamic>> callTool({
    required String system,
    required String user,
    required ToolSpec tool,
    required Duration timeout,
  }) async {
    toolCalls++;
    lastSystem = system;
    lastUser = user;
    final args = nextArgs;
    await _wait();
    final e = nextError;
    if (e != null) {
      nextError = null;
      throw e;
    }
    return args;
  }

  @override
  Future<String> generate({
    required String system,
    required String user,
    required Duration timeout,
    int maxOutputTokens = 256,
  }) async {
    generateCalls++;
    lastSystem = system;
    lastUser = user;
    final text = nextText;
    await _wait();
    final e = nextError;
    if (e != null) {
      nextError = null;
      throw e;
    }
    return text;
  }

  Future<void> _wait() async {
    concurrentJobs++;
    if (concurrentJobs > maxConcurrentJobs) maxConcurrentJobs = concurrentJobs;
    try {
      final h = hold;
      if (h == null) return;
      final inflight = Completer<Object>();
      _inflight = inflight;
      final result = await Future.any<Object?>([
        h.future.then((_) => null),
        inflight.future,
      ]);
      _inflight = null;
      if (result != null) throw result;
    } finally {
      concurrentJobs--;
    }
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    if (ignoreCancel) return;
    final h = cancelHold;
    if (h != null) await h.future;
    final i = _inflight;
    if (i != null && !i.isCompleted) i.complete(const GemmaCancelled());
  }

  @override
  Future<void> unload() async {
    unloadCalls++;
    events.add('unload');
    await cancel();
    loaded = false;
  }
}

class FakeGemmaInstaller implements GemmaInstaller {
  bool installed = false;
  bool ignoreCancel = false, skipInstall = false;
  Object? checkError;
  Completer<void>? checkHold;
  Completer<bool>? firstCheck;
  int activateCalls = 0, installCalls = 0;
  Object? failWith;
  Completer<void>? hold;

  @override
  Future<bool> isInstalled() async {
    final e = checkError;
    if (e != null) throw e;
    if (checkHold != null) {
      firstCheck = Completer<bool>();
      return firstCheck!.future;
    }
    return installed;
  }

  @override
  Future<void> activate() async => activateCalls++;

  @override
  Future<void> install({
    required void Function(int percent) onProgress,
    required GemmaCancelSignal cancel,
  }) async {
    installCalls++;
    for (final p in const [10, 50, 100]) {
      if (cancel.isCancelled && !ignoreCancel) {
        throw const GemmaDownloadCancelled();
      }
      onProgress(p);
      final h = hold;
      if (h != null) await h.future;
    }
    if (cancel.isCancelled && !ignoreCancel) {
      throw const GemmaDownloadCancelled();
    }
    final f = failWith;
    if (f != null) throw f;
    if (!skipInstall) installed = true;
  }
}
