import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_library/application/library_module.dart';
import 'package:pili_aurora_next/features/content_library/application/paged_feed.dart';
import 'package:pili_aurora_next/features/subscriptions/application/subscription_cleanup.dart';
import 'package:pili_aurora_next/features/subscriptions/data/subscription_repository.dart';
import 'package:pili_aurora_next/features/subscriptions/domain/subscription.dart';
import 'package:pili_aurora_next/features/subscriptions/domain/subscription_video.dart';
import 'package:pili_aurora_next/features/subscriptions/domain/subscription_query.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

export 'package:pili_aurora_next/features/subscriptions/domain/subscription.dart';
export 'package:pili_aurora_next/features/subscriptions/domain/subscription_video.dart';
export 'package:pili_aurora_next/features/subscriptions/domain/subscription_query.dart';

typedef SubscriptionState = FeedState<Object, SubItemModel?>;

class SubscriptionCancellation {
  const SubscriptionCancellation({this.localFailed = false});
  final bool localFailed;
  String get message => localFailed ? '取消订阅成功，本地记录清理失败' : '取消订阅成功';
}

class SubscriptionCleanupReport {
  const SubscriptionCleanupReport(
    this.result,
    this.hideInvalid,
    this.localFailures,
  );
  final SubscriptionCleanupResult result;
  final bool hideInvalid;
  final int localFailures;
  String get message =>
      result.removed == 0 &&
          result.hidden == 0 &&
          result.failed == 0 &&
          result.pending == 0
      ? '没有需要清理的失效内容'
      : '已取消 ${result.removed} 个订阅'
            '${hideInvalid ? '，本地隐藏 ${result.hidden} 个失效视频' : ''}'
            '${result.failed > 0 ? '；${result.failed} 个订阅清理失败' : ''}'
            '${result.pending > 0 ? '；${result.pending} 个取消结果待确认，请刷新订阅核对' : ''}'
            '${localFailures > 0 ? '；$localFailures 项本地记录清理失败' : ''}';
}

/// 多页面共用写入锁和失效信号；页面关闭不撤销已发出的远端写入。
class SubscriptionLibrary extends LibraryModule {
  SubscriptionLibrary(this.repository);
  final SubscriptionRepository repository;
  int revision = 0;
  @override
  bool owns(Account account) => identical(account, Accounts.main);

  Future<SubscriptionCancellation> _cancel(
    Account account,
    SubItemModel item,
  ) async {
    final result = await repository.cancel(account, item);
    result.data;
    try {
      await repository.hidden(account).remove(item.type!, item.id!);
      return const SubscriptionCancellation();
    } catch (_) {
      // 远端已确认成功，本地缓存失败不能诱导用户重复取消。
      return const SubscriptionCancellation(localFailed: true);
    }
  }

  Future<LoadingState<T>> _write<T>(
    Account account,
    Future<LoadingState<T>> Function() send,
  ) => write(account, () async {
    final result = await send();
    if (result.isSuccess && owns(account)) revision++;
    return result;
  });

  Future<LoadingState<SubscriptionCancellation>> cancel(
    Account account,
    SubItemModel item,
  ) => _write(account, () async {
    try {
      return Success(await _cancel(account, item));
    } on Error catch (error) {
      return error;
    }
  });

  Future<LoadingState<SubscriptionCleanupReport>> clean(
    Account account, {
    required bool hideInvalid,
    required bool Function() isCurrent,
    required void Function(String) onProgress,
  }) => _write(account, () async {
    bool current() => owns(account) && isCurrent();
    onProgress('正在读取全部订阅');
    final snapshot = await loadSubscriptionSnapshot(
      (page) => current()
          ? repository.subscriptions(account, page)
          : Future.value(const Error('账号或页面已更新')),
    );
    if (!current()) return const Error('账号或页面已更新');
    if (snapshot is! Success<List<SubItemModel>>) return snapshot as Error;
    var localFailures = 0;
    final cleaner = SubscriptionCleaner(
      loadContents: (item, page) => current()
          ? repository.contents(account, item, page)
          : Future.value(const Error('账号或页面已更新')),
      checkVideo: (aid) => current()
          ? repository.available(account, aid)
          : Future.value(const Error('账号或页面已更新')),
      cancel: (item) async {
        if (!current()) return const Error('账号或页面已更新');
        try {
          if ((await _cancel(account, item)).localFailed) localFailures++;
          return const Success(null);
        } on Error catch (error) {
          return error;
        }
      },
      saveHidden: (item, media) => current()
          ? repository.hidden(account).add(item.type!, item.id!, media)
          : Future.value(0),
    );
    final result = await cleaner.run(
      snapshot.response,
      hideInvalid: hideInvalid,
      isCurrent: current,
      onProgress: (processed, total) {
        if (current()) onProgress('正在检查 $processed/$total 个订阅');
      },
    );
    return Success(
      SubscriptionCleanupReport(result, hideInvalid, localFailures),
    );
  });
}

final subscriptionLibraryProvider = Provider<SubscriptionLibrary>((ref) {
  final library = SubscriptionLibrary(SubscriptionRepository());
  ref.onDispose(library.close);
  return library;
});

final subscriptionFeedProvider = AsyncNotifierProvider.autoDispose
    .family<SubscriptionFeed, SubscriptionState, SubscriptionQuery>(
      SubscriptionFeed.new,
      retry: (_, _) => null,
    );

class SubscriptionFeed extends PagedFeed<Object, SubItemModel?> {
  SubscriptionFeed(this.query);
  final SubscriptionQuery query;
  late SubscriptionLibrary _library;
  int _revision = 0;
  @override
  Account watchAccount() {
    _library = ref.watch(subscriptionLibraryProvider);
    _revision = _library.revision;
    final account = ref.watch(mainAccountProvider);
    final owner = ref;
    final subscription = _library.changes.listen((changed) {
      if (owner.mounted && identical(account, changed)) owner.invalidateSelf();
    });
    owner.onDispose(subscription.cancel);
    return account;
  }

  @override
  bool ownsAccount(Account account) =>
      _library.owns(account) && _library.revision == _revision;
  @override
  bool get endOnEmptyBudget => false;
  @override
  Object itemKey(Object item) => switch (item) {
    SubItemModel(:final type, :final id) => (type, id),
    SubDetailItemModel(:final id) => id ?? item,
    _ => item,
  };
  @override
  Future<FeedPage<Object, SubItemModel?>> fetch(
    Account account,
    Object? cursor,
  ) async {
    final owner = ref;
    final page = cursor as int? ?? 1;
    if (query.id == null) {
      final data = (await _library.repository.subscriptions(
        account,
        page,
      )).data;
      if (data.hasMore == null) throw const Error('订阅分页信息不完整，请稍后重试');
      return FeedPage(
        data.list ?? [],
        metadata: null,
        next: data.hasMore! ? page + 1 : null,
      );
    }
    if (query.id! <= 0) throw const Error('合集标识无效，请重新打开页面');
    final data = (await _library.repository.detail(
      account,
      query.id!,
      page,
    )).data;
    // 隐藏记录只读取发起账号；切号或释放后不触碰本地缓存、不补页。
    if (!owner.mounted || !ownsAccount(account)) throw const Error('账号或查询已更新');
    if (data.info == null) throw const Error('合集信息不完整，请重试');
    final raw = data.medias ?? [];
    final total = data.info?.mediaCount;
    final next =
        raw.length < SubscriptionRepository.pageSize ||
            (total != null && page * SubscriptionRepository.pageSize >= total)
        ? null
        : page + 1;
    final hidden = _library.repository.hideInvalid
        ? _library.repository.hidden(account).read(21, query.id!)
        : const <String>{};
    return FeedPage(
      raw.where((item) => !hidden.contains('2:${item.id}')),
      metadata: data.info,
      next: next,
    );
  }

  bool canCancel(SubscriptionState source, SubItemModel item) =>
      query.id == null &&
      isCurrent(source) &&
      !source.loadingMore &&
      source.items.contains(item) &&
      (item.id ?? 0) > 0 &&
      const [11, 21].contains(item.type);
}

class SubscriptionOperationState {
  const SubscriptionOperationState({
    this.busy = false,
    this.cleaning = false,
    this.progress = '',
  });
  final bool busy;
  final bool cleaning;
  final String progress;
}

final subscriptionOperationsProvider =
    NotifierProvider.autoDispose<
      SubscriptionOperations,
      SubscriptionOperationState
    >(SubscriptionOperations.new);

class SubscriptionOperations extends Notifier<SubscriptionOperationState> {
  late Account _account;
  late SubscriptionLibrary _library;
  Object _generation = Object();
  bool get hideInvalid => _library.repository.hideInvalid;
  @override
  SubscriptionOperationState build() {
    _generation = Object();
    _account = ref.watch(mainAccountProvider);
    _library = ref.watch(subscriptionLibraryProvider);
    return const SubscriptionOperationState();
  }

  Future<LoadingState<T>> _run<T>(
    Account account,
    bool cleaning,
    Future<LoadingState<T>> Function(bool Function(), void Function(String))
    send,
  ) async {
    if (state.busy ||
        !identical(account, _account) ||
        !_library.owns(account)) {
      return const Error('操作进行中或账号已更新');
    }
    final owner = ref, generation = _generation;
    bool current() =>
        owner.mounted &&
        identical(generation, _generation) &&
        _library.owns(account);
    state = SubscriptionOperationState(busy: true, cleaning: cleaning);
    try {
      return await send(current, (progress) {
        if (current()) {
          state = SubscriptionOperationState(
            busy: true,
            cleaning: true,
            progress: progress,
          );
        }
      });
    } finally {
      if (current()) state = const SubscriptionOperationState();
    }
  }

  Future<LoadingState<SubscriptionCancellation>> cancel(
    SubscriptionState source,
    SubItemModel item, {
    required bool Function() isCurrent,
  }) {
    if (!isCurrent() ||
        !source.items.contains(item) ||
        (item.id ?? 0) <= 0 ||
        !const [11, 21].contains(item.type)) {
      return Future.value(const Error('账号或订阅已更新，请重新打开'));
    }
    return _run(
      source.account,
      false,
      (_, _) => _library.cancel(source.account, item),
    );
  }

  Future<LoadingState<SubscriptionCleanupReport>> clean(
    Account account, {
    required bool hideInvalid,
    required bool Function() isCurrent,
  }) => _run(
    account,
    true,
    (current, progress) => _library.clean(
      account,
      hideInvalid: hideInvalid,
      isCurrent: () => current() && isCurrent(),
      onProgress: progress,
    ),
  );
}
