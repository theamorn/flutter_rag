import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';

import 'flutter_gemma_installer.dart';
import 'gemma_runtime.dart';
import 'gemma_tool.dart';

/// Fresh native conversation per job. Completion includes native cleanup.
class FlutterGemmaRuntime implements GemmaRuntime {
  FlutterGemmaRuntime({Future<InferenceModel> Function()? modelLoader})
    : _modelLoader = modelLoader ?? _loadNative;

  final Future<InferenceModel> Function() _modelLoader;
  InferenceModel? _model;
  _NativeJob? _job;

  static Future<InferenceModel> _loadNative() async {
    await FlutterGemmaInstaller.ensureInitialized();
    return FlutterGemma.getActiveModel(maxTokens: 2048, preferredBackend: PreferredBackend.gpu);
  }

  @override
  bool get isLoaded => _model != null;
  @override
  String? get backendLabel => _model?.activeBackend?.name;
  @override
  Future<void> load() async {
    _model ??= await _modelLoader();
  }

  @override
  Future<Map<String, dynamic>> callTool({
    required String system,
    required String user,
    required ToolSpec tool,
    required Duration timeout,
  }) {
    final prose = StringBuffer();
    return _run<Map<String, dynamic>>(
      system: system,
      user: user,
      timeout: timeout,
      tools: [Tool(name: tool.name, description: tool.description, parameters: tool.parameters)],
      maxOutputTokens: 256,
      onResponse: (response, finish) {
        final calls = switch (response) {
          FunctionCallResponse c => [c],
          ParallelFunctionCallResponse p => p.calls,
          _ => <FunctionCallResponse>[],
        };
        for (final call in calls) {
          if (call.name == tool.name) {
            finish(call.args);
            return;
          }
        }
        if (response is TextResponse) prose.write(response.token);
      },
      onDone: () => throw GemmaNoToolCall(prose.toString()),
    );
  }

  @override
  Future<String> generate({
    required String system,
    required String user,
    required Duration timeout,
    int maxOutputTokens = 256,
  }) {
    final text = StringBuffer();
    return _run<String>(
      system: system,
      user: user,
      timeout: timeout,
      tools: const [],
      maxOutputTokens: maxOutputTokens,
      onResponse: (r, _) {
        if (r is TextResponse) text.write(r.token);
      },
      onDone: () => text.toString(),
    );
  }

  Future<T> _run<T>({
    required String system,
    required String user,
    required Duration timeout,
    required List<Tool> tools,
    required int maxOutputTokens,
    required void Function(ModelResponse, void Function(T)) onResponse,
    required T Function() onDone,
  }) async {
    final model = _model;
    if (model == null) throw StateError('Gemma is not loaded');
    if (_job != null) {
      throw StateError('A Gemma conversation is already running');
    }
    final job = _NativeJob();
    _job = job;
    // Deadline includes both native await gaps, not just stream decoding.
    final deadline = Timer(timeout, () => job.abort(GemmaTimeout(timeout)));
    try {
      job.chat = await model.createChat(
        temperature: 0,
        topK: 1,
        tools: tools,
        supportsFunctionCalls: tools.isNotEmpty,
        modelType: ModelType.gemma4,
        toolChoice: tools.isEmpty ? ToolChoice.auto : ToolChoice.required,
        isThinking: false,
        systemInstruction: system,
        maxOutputTokens: maxOutputTokens,
      );
      job.check();
      await job.chat!.addQueryChunk(Message.text(text: user, isUser: true));
      job.check();
      final result = Completer<T>();
      // Attach error handlers before listening or any cancellation can happen.
      final completed = Future.any<T>([
        result.future,
        job.aborted.future.then<T>((error) => throw error),
      ]);
      job.sub = job.chat!.generateChatResponseAsync().listen(
        (r) {
          if (result.isCompleted) return;
          try {
            onResponse(r, (value) {
              if (!result.isCompleted) result.complete(value);
            });
          } catch (e, stack) {
            if (!result.isCompleted) result.completeError(e, stack);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        },
        onDone: () {
          if (result.isCompleted) return;
          try {
            result.complete(onDone());
          } catch (e, stack) {
            result.completeError(e, stack);
          }
        },
      );
      final value = await completed;
      job.check();
      return value;
    } catch (_) {
      job.check();
      rethrow;
    } finally {
      deadline.cancel();
      try {
        await job.close();
      } finally {
        if (identical(_job, job)) _job = null;
        job.finished.complete();
      }
    }
  }

  @override
  Future<void> cancel() async {
    final job = _job;
    if (job == null) return;
    job.abort(const GemmaCancelled());
    await job.finished.future;
  }

  @override
  Future<void> unload() async {
    await cancel();
    final model = _model;
    _model = null;
    await model?.close();
  }
}

class _NativeJob {
  InferenceChat? chat;
  StreamSubscription<ModelResponse>? sub;
  final aborted = Completer<Object>();
  final finished = Completer<void>();
  Object? error;
  Future<void>? _stop;

  void abort(Object reason) {
    if (error != null) return;
    error = reason;
    aborted.complete(reason);
    // Stop can release a blocked addQueryChunk; createChat has no handle yet.
    if (chat != null) unawaited(stop());
  }

  void check() {
    final e = error;
    if (e != null) throw e;
  }

  Future<void> stop() => _stop ??= () async {
    try {
      await chat?.stopGeneration();
    } catch (_) {
      /* Still cancel and close. */
    }
  }();
  Future<void> close() async {
    await stop();
    try {
      await sub?.cancel();
    } finally {
      await chat?.close();
    }
  }
}
