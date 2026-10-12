import 'package:flutter/foundation.dart';

import '../core/transaction.dart';
import 'result_source.dart';

enum PagerStatus {
  idle,
  loadingFirst,
  ready,
  loadingMore,
  end,
  firstPageError,
  nextPageError,
}

/// First page of 100, then pages of 20 (spec §11). One request at a time;
/// responses from an earlier [start] are discarded; rows de-duplicated by id.
class ResultPager extends ChangeNotifier {
  static const int firstPageSize = 100;
  static const int pageSize = 20;

  final List<Transaction> _items = [];
  final Set<String> _ids = {};
  ResultSource? _source;
  int _offset = 0;
  int _generation = 0;
  PagerStatus _status = PagerStatus.idle;
  Object? _error;
  bool _disposed = false;

  List<Transaction> get items => List.unmodifiable(_items);
  PagerStatus get status => _status;
  Object? get error => _error;
  bool get canLoadMore => _status == PagerStatus.ready;

  /// Replaces the list with [source]'s first page.
  Future<void> start(ResultSource source) {
    final gen = ++_generation;
    _source = source;
    _items.clear();
    _ids.clear();
    _offset = 0;
    _error = null;
    _setStatus(PagerStatus.loadingFirst);
    return _load(gen, source, firstPageSize, PagerStatus.firstPageError);
  }

  /// Appends the next page. Does nothing unless [canLoadMore].
  Future<void> loadMore() {
    final source = _source;
    if (!canLoadMore || source == null) return Future.value();
    _setStatus(PagerStatus.loadingMore);
    return _load(_generation, source, pageSize, PagerStatus.nextPageError);
  }

  Future<void> retry() async {
    final source = _source;
    if (source == null) return;
    if (_status == PagerStatus.firstPageError) {
      await start(source);
    } else if (_status == PagerStatus.nextPageError) {
      _setStatus(PagerStatus.ready);
      await loadMore();
    }
  }

  /// Empties the list and invalidates in-flight requests.
  void reset() {
    _generation++;
    _source = null;
    _items.clear();
    _ids.clear();
    _offset = 0;
    _error = null;
    _setStatus(PagerStatus.idle);
  }

  Future<void> _load(int gen, ResultSource source, int size,
      PagerStatus onError) async {
    try {
      final page = await source.fetch(_offset, size);
      if (gen != _generation || _disposed) return;
      _offset += size;
      for (final t in page.rows) {
        if (_ids.add(t.id)) _items.add(t);
      }
      _setStatus(page.reachedEnd ? PagerStatus.end : PagerStatus.ready);
    } catch (e) {
      if (gen != _generation || _disposed) return;
      _error = e;
      _setStatus(onError);
    }
  }

  void _setStatus(PagerStatus status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
