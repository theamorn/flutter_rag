import 'gemma_tool.dart';

class GemmaCancelled implements Exception {
  const GemmaCancelled();

  @override
  String toString() => 'Advanced request cancelled';
}

class GemmaNoToolCall implements Exception {
  GemmaNoToolCall(this.prose);

  /// What the model said instead of calling the tool.
  final String prose;

  @override
  String toString() => 'Gemma answered without calling the tool';
}

class GemmaTimeout implements Exception {
  const GemmaTimeout(this.after);

  final Duration after;

  @override
  String toString() => 'Gemma timed out after ${after.inSeconds} s';
}

/// One LiteRT-LM conversation and generation at a time. Each job opens a
/// fresh chat and closes it when done. [cancel] stops the running job, which
/// then completes with [GemmaCancelled]. A timeout must stop native generation
/// and close the conversation before throwing [GemmaTimeout]; a Dart timeout
/// alone does not satisfy this contract.
abstract interface class GemmaRuntime {
  bool get isLoaded;

  /// e.g. "gpu" or "cpu", once loaded.
  String? get backendLabel;

  Future<void> load();

  Future<Map<String, dynamic>> callTool({
    required String system,
    required String user,
    required ToolSpec tool,
    required Duration timeout,
  });

  Future<String> generate({
    required String system,
    required String user,
    required Duration timeout,
    int maxOutputTokens = 256,
  });

  Future<void> cancel();

  /// Cancels, closes the chat and the model. The downloaded file stays.
  Future<void> unload();
}
