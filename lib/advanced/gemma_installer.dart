/// Cancels a download; listeners run once.
class GemmaCancelSignal {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final l in listeners) {
      l();
    }
  }

  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}

class GemmaDownloadCancelled implements Exception {
  const GemmaDownloadCancelled();
}

abstract interface class GemmaInstaller {
  Future<bool> isInstalled();

  /// Downloads the model; [onProgress] gets 0-100. Throws
  /// [GemmaDownloadCancelled] if [cancel] fires.
  Future<void> install({
    required void Function(int percent) onProgress,
    required GemmaCancelSignal cancel,
  });

  /// Makes the installed model the active one (after an app restart).
  Future<void> activate();
}
