import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/member_space/data/space_repository.dart';
import 'package:pili_aurora_next/features/member_space/domain/space_tabs.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/member/tab_type.dart';
import 'package:pili_aurora_next/models/remote/space/space/data.dart';
import 'package:pili_aurora_next/models/remote/space/space/setting.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

// 同一 MID 的两个路由独立刷新；凭据变化时废弃旧快照与在途交付。
typedef SpaceQuery = ({Object owner, int mid, String? fromViewAid});

final spaceProvider = AsyncNotifierProvider.autoDispose
    .family<MemberSpace, SpaceSnapshot, SpaceQuery>(
      MemberSpace.new,
      retry: (_, _) => null,
    );

class SpaceSnapshot {
  SpaceSnapshot({
    required this.account,
    required this.mid,
    required this.data,
    this.error,
    required this.tabs,
    required this.relation,
    required this.isFollowed,
  });

  factory SpaceSnapshot.loaded(Account account, int mid, SpaceData data) {
    final relation = data.card?.relation;
    return SpaceSnapshot(
      account: account,
      mid: mid,
      data: data,
      tabs: SpaceTabs(data, Pref.memberTab),
      relation: switch (data.relation) {
        -1 => 128,
        -999 => data.guestRelation == -1 ? -1 : 0,
        _ when relation?.isFollow == 1 =>
          data.relSpecial == 1 ? -10 : relation?.status ?? 2,
        _ => data.relation ?? 0,
      },
      isFollowed: relation?.isFollowed,
    );
  }

  final Account account;
  final int mid;
  final SpaceData? data;
  final String? error;
  final SpaceTabs tabs;
  final int relation;
  final int? isFollowed;
  bool get isFollow => relation != 0 && relation != 128 && relation != -1;
  String? get username => data == null ? error : data?.card?.name ?? '';
  String? get userAvatar => data?.card?.face;
  SpaceSetting? get spaceSetting => mid == account.mid ? data?.setting : null;

  SpaceSnapshot updateRelation(int relation, {bool removedFan = false}) =>
      SpaceSnapshot(
        account: account,
        mid: mid,
        data: data,
        error: error,
        tabs: tabs,
        relation: relation,
        isFollowed: removedFan ? null : isFollowed,
      );
}

class MemberSpace extends AsyncNotifier<SpaceSnapshot> {
  MemberSpace(this.query);
  final SpaceQuery query;
  late Object _generation;
  Object? _relationOperation;
  bool _claimingExperience = false;
  final _reservations = <int>{};

  @override
  Future<SpaceSnapshot> build() async {
    final account = ref.watch(mainAccountProvider);
    _generation = Object();
    final result = await ref
        .read(spaceRepositoryProvider)
        .space(
          account,
          query.mid,
          query.fromViewAid,
        );
    return switch (result) {
      Success(:final response) => SpaceSnapshot.loaded(
        account,
        query.mid,
        response,
      ),
      Error(:final errMsg) => SpaceSnapshot(
        account: account,
        mid: query.mid,
        data: null,
        error: errMsg,
        tabs: SpaceTabs(null, MemberTabType.def),
        relation: 0,
        isFollowed: null,
      ),
      Loading() => throw const Error('空间请求没有返回结果'),
    };
  }

  SpaceSnapshot? get snapshot =>
      state.isLoading || state.hasError ? null : state.value;

  bool Function() capture() {
    final generation = _generation;
    final account = snapshot?.account;
    return () =>
        ref.mounted &&
        identical(generation, _generation) &&
        account != null &&
        identical(account, snapshot?.account) &&
        identical(account, ref.read(mainAccountProvider));
  }

  Future<void> refresh() async {
    _generation = Object();
    ref.invalidateSelf();
    await future;
  }

  Future<void> runRelation(
    Future<void> Function(SpaceSnapshot, bool Function()) action,
  ) async {
    final source = snapshot;
    if (source == null || _relationOperation != null) return;
    final operation = _relationOperation = Object();
    try {
      await action(source, capture());
    } finally {
      if (identical(_relationOperation, operation)) _relationOperation = null;
    }
  }

  Future<LoadingState<void>> writeRelation(Account account, int action) =>
      ref.read(spaceRepositoryProvider).relation(account, query.mid, action);

  void updateRelation(int relation, {bool removedFan = false}) {
    final source = snapshot;
    if (source != null) {
      state = AsyncData(
        source.updateRelation(relation, removedFan: removedFan),
      );
    }
  }

  Future<LoadingState<void>?> reserve(int sid, bool isFollow) async {
    final account = snapshot?.account;
    if (account == null || !_reservations.add(sid)) return null;
    try {
      return await ref
          .read(spaceRepositoryProvider)
          .reserve(account, sid, isFollow);
    } finally {
      _reservations.remove(sid);
    }
  }

  Future<LoadingState<void>?> claimExperience() async {
    final source = snapshot;
    if (source == null ||
        source.data == null ||
        !source.account.isLogin ||
        query.mid != source.account.mid ||
        _claimingExperience) {
      return null;
    }
    _claimingExperience = true;
    try {
      return await ref
          .read(spaceRepositoryProvider)
          .claimExperience(source.account);
    } finally {
      _claimingExperience = false;
    }
  }
}
