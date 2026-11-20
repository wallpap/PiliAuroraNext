import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_library/application/library_module.dart';
import 'package:pili_aurora_next/features/content_library/application/paged_feed.dart';
import 'package:pili_aurora_next/features/history/data/history_repository.dart';
import 'package:pili_aurora_next/features/history/domain/list.dart';
import 'package:pili_aurora_next/features/history/domain/tab.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

class HistoryLibrary extends LibraryModule {
  HistoryLibrary(this._repository);
  final HistoryRepository _repository;
  static HistoryLibrary? _applicationLibrary;
  static HistoryLibrary get legacy =>
      _applicationLibrary ??= HistoryLibrary(HistoryRepository());
  static Future<void> closeApplication() =>
      _applicationLibrary?.close() ?? Future.value();
  final _pauseChanges =
      StreamController<({Account account, bool paused})>.broadcast(sync: true);
  Stream<({Account account, bool paused})> get pauseChanges =>
      _pauseChanges.stream;
  int _statusVersion = 0;
  final _savingPauseFor = Set<Account>.identity();
  Future<void>? _cacheInFlight;
  Future<void> _cache(Account account, bool paused, int version) async {
    while (_cacheInFlight != null) {
      final pending = _cacheInFlight!;
      try {
        await pending;
      } catch (_) {
        // 前项失败由原调用方消费。
      }
    }
    if (version != _statusVersion || !owns(account)) return;
    final operation = _repository.cachePause(paused);
    _cacheInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_cacheInFlight, operation)) _cacheInFlight = null;
    }
  }

  @override
  bool owns(Account account) =>
      !isClosed && identical(account, Accounts.history);

  Future<void> syncActiveAccountStatus() async {
    final account = Accounts.history;
    if (account.isLogin) await status(account);
  }

  /// 启动和页面使用同一查询代次；持久化失败沿原 Future 交付。
  Future<LoadingState<bool>> status(Account account) async {
    if (!owns(account) || !account.isLogin) return const Error('账号已切换或未登录');
    if (_savingPauseFor.contains(account)) return const Error('历史状态已更新');
    final version = ++_statusVersion;
    final result = await _repository.status(account);
    if (version != _statusVersion || !owns(account)) {
      return const Error('历史状态已更新');
    }
    if (result case Success(:final response)) {
      await _cache(account, response, version);
      if (version == _statusVersion &&
          owns(account) &&
          !_pauseChanges.isClosed) {
        _pauseChanges.add((account: account, paused: response));
      }
    }
    return result;
  }

  Future<LoadingState<void>> pause(Account account, bool paused) =>
      write(account, () async {
        final version = ++_statusVersion;
        _savingPauseFor.add(account);
        try {
          final result = await _repository.pause(account, paused);
          if (result.isSuccess && owns(account)) {
            _pauseChanges.add((account: account, paused: paused));
            try {
              await _cache(account, paused, version);
            } catch (error, stack) {
              return Error('历史状态已保存，本地缓存同步失败', cause: error, stackTrace: stack);
            }
          }
          return result;
        } finally {
          _savingPauseFor.remove(account);
        }
      });
  Future<LoadingState<void>> clear(Account account) =>
      write(account, () => _repository.clear(account));
  Future<LoadingState<void>> remove(
    Account account,
    Iterable<HistoryItemModel> items,
  ) {
    final ids = <String>[];
    for (final item in items) {
      final business = item.history.business;
      if (item.kid == null || business == null || business.isEmpty) {
        return Future.value(const Error('历史记录标识无效'));
      }
      ids.add('${business}_${item.kid}');
    }
    if (ids.isEmpty) return Future.value(const Error('请选择历史记录'));
    return write(account, () => _repository.remove(account, ids));
  }

  @override
  Future<void> close() => Future.wait([
    super.close(),
    _pauseChanges.close(),
    ?_cacheInFlight,
  ]);
}

final historyLibraryProvider = Provider<HistoryLibrary>(
  (ref) => HistoryLibrary.legacy,
);
final historyPauseProvider =
    AsyncNotifierProvider.autoDispose<HistoryPause, bool>(
      HistoryPause.new,
      retry: (_, _) => null,
    );

class HistoryPause extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final account = ref.watch(historyAccountProvider);
    final library = ref.watch(historyLibraryProvider);
    final owner = ref;
    bool? confirmed;
    final sub = library.pauseChanges.listen((value) {
      if (owner.mounted && identical(account, value.account)) {
        confirmed = value.paused;
        state = AsyncData(value.paused);
      }
    });
    owner.onDispose(sub.cancel);
    final result = await library.status(account);
    return confirmed ?? result.data;
  }

  Future<LoadingState<void>> set(bool paused) => ref
      .read(historyLibraryProvider)
      .pause(ref.read(historyAccountProvider), paused);
}

typedef HistoryQuery = ({
  Object owner,
  String type,
  String keyword,
  bool search,
});
typedef HistoryState = FeedState<HistoryItemModel, List<HistoryTab>>;
final historyFeedProvider = AsyncNotifierProvider.autoDispose
    .family<HistoryFeed, HistoryState, HistoryQuery>(
      HistoryFeed.new,
      retry: (_, _) => null,
    );

class HistoryFeed extends PagedFeed<HistoryItemModel, List<HistoryTab>> {
  HistoryFeed(this.query);
  final HistoryQuery query;
  late HistoryLibrary _library;
  @override
  Account watchAccount() {
    _library = ref.watch(historyLibraryProvider);
    final account = ref.watch(historyAccountProvider);
    final owner = ref;
    final subscription = _library.changes.listen((changed) {
      if (owner.mounted && identical(account, changed)) owner.invalidateSelf();
    });
    owner.onDispose(subscription.cancel);
    return account;
  }

  @override
  bool ownsAccount(Account account) => _library.owns(account);
  @override
  Object itemKey(HistoryItemModel item) => (item.history.business, item.kid);
  @override
  Future<FeedPage<HistoryItemModel, List<HistoryTab>>> fetch(
    Account account,
    Object? cursor,
  ) async {
    final data = await _library._repository.page(
      account,
      type: query.type,
      keyword: query.keyword,
      search: query.search,
      cursor: cursor,
    );
    final items = data.list ?? [];
    final tabs = List<HistoryTab>.unmodifiable(data.tab ?? const []);
    Object? next;
    if (query.search) {
      if (items.length >= 20) next = (cursor as int? ?? 1) + 1;
    } else if (items.isNotEmpty) {
      final last = items.last;
      if (last.history.oid != null && last.viewAt != null) {
        next = (last.history.oid!, last.viewAt!);
      }
      if (next == cursor) next = null;
    }
    return FeedPage(items, metadata: tabs, next: next);
  }

  @override
  List<HistoryTab> mergeMetadata(
    List<HistoryTab> previous,
    List<HistoryTab> next,
  ) => next.isEmpty ? previous : next;

  Future<LoadingState<void>> remove(
    HistoryState source,
    Iterable<HistoryItemModel> items,
  ) {
    final selected = items.toList();
    if (!isCurrent(source) ||
        selected.any((item) => !source.items.contains(item))) {
      return Future.value(const Error('历史列表已更新'));
    }
    return _library.remove(source.account, selected);
  }
}
