import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/sponsor_block/application/sponsor_block.dart';
import 'package:pili_aurora_next/features/sponsor_block/data/sponsor_block_preferences.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/segment_type.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/skip_type.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/segment_response/user_info.dart';
import 'package:pili_aurora_next/services/logger.dart';

final sponsorBlockSettingsProvider =
    NotifierProvider.autoDispose<
      SponsorBlockSettingsNotifier,
      SponsorBlockSettings
    >(
      SponsorBlockSettingsNotifier.new,
    );

class SponsorBlockSettings {
  SponsorBlockSettings({
    required this.limit,
    required this.behaviors,
    required this.colors,
    required this.identity,
    required this.toast,
    required this.track,
    LoadingState<void>? uptime,
    LoadingState<UserInfo>? userInfo,
  }) : uptime = uptime ?? LoadingState.loading(),
       userInfo = userInfo ?? LoadingState.loading();

  final double limit;
  final Map<SegmentType, SkipType> behaviors;
  final List<Color> colors;
  final SponsorBlockIdentity identity;
  final bool toast;
  final bool track;
  final LoadingState<void> uptime;
  final LoadingState<UserInfo> userInfo;

  SponsorBlockSettings _copy({
    double? limit,
    Map<SegmentType, SkipType>? behaviors,
    List<Color>? colors,
    SponsorBlockIdentity? identity,
    bool? toast,
    bool? track,
    LoadingState<void>? uptime,
    LoadingState<UserInfo>? userInfo,
  }) => SponsorBlockSettings(
    limit: limit ?? this.limit,
    behaviors: behaviors ?? this.behaviors,
    colors: colors ?? this.colors,
    identity: identity ?? this.identity,
    toast: toast ?? this.toast,
    track: track ?? this.track,
    uptime: uptime ?? this.uptime,
    userInfo: userInfo ?? this.userInfo,
  );
}

class SponsorBlockSettingsNotifier extends Notifier<SponsorBlockSettings> {
  Object? _owner;
  int _uptimeVersion = 0;
  int _userVersion = 0;
  final _saving = <SponsorBlockPreference, Object>{};

  @override
  SponsorBlockSettings build() {
    final owner = _owner = Object();
    ref.onDispose(() {
      if (identical(_owner, owner)) _owner = null;
    });
    unawaited(
      Future.microtask(() {
        if (!_isCurrent(owner)) return;
        unawaited(refreshUptime());
        unawaited(refreshUserInfo());
      }),
    );
    return SponsorBlockSettings(
      limit: SponsorBlockPreferences.limit,
      behaviors: Map.unmodifiable(SponsorBlockPreferences.behaviors),
      colors: List.unmodifiable(SponsorBlockPreferences.colors),
      identity: SponsorBlock.identity,
      toast: SponsorBlockPreferences.toast,
      track: SponsorBlockPreferences.track,
    );
  }

  bool _isCurrent(Object? owner) =>
      owner != null && identical(_owner, owner) && ref.mounted;

  Future<void> refreshUptime() async {
    final owner = _owner;
    if (!_isCurrent(owner)) return;
    final version = ++_uptimeVersion;
    final server = state.identity.server;
    state = state._copy(uptime: LoadingState.loading());
    final result = await SponsorBlock.uptimeStatus(server: server);
    if (_isCurrent(owner) &&
        version == _uptimeVersion &&
        state.identity.server == server) {
      state = state._copy(uptime: result);
    }
  }

  Future<void> refreshUserInfo() async {
    final owner = _owner;
    if (!_isCurrent(owner)) return;
    final version = ++_userVersion;
    final identity = state.identity;
    state = state._copy(userInfo: LoadingState.loading());
    final result = await SponsorBlock.userInfo(
      const ['viewCount', 'minutesSaved', 'segmentCount'],
      userId: identity.userId,
      server: identity.server,
    );
    if (_isCurrent(owner) &&
        version == _userVersion &&
        state.identity == identity) {
      state = state._copy(userInfo: result);
    }
  }

  Future<LoadingState<void>?> saveLimit(double? value) async {
    if (value == null || !value.isFinite || value < 0) {
      return const Error('请输入大于或等于 0 的有效秒数');
    }
    return _save(
      SponsorBlockPreference.limit,
      value,
      () => state._copy(limit: value),
    );
  }

  Future<LoadingState<void>?> saveToast(bool value) => _save(
    SponsorBlockPreference.toast,
    value,
    () => state._copy(toast: value),
  );

  Future<LoadingState<void>?> saveTracking(bool value) => _save(
    SponsorBlockPreference.track,
    value,
    () => state._copy(track: value),
  );

  Future<LoadingState<void>?> saveUserId(String value) async {
    if (!RegExp(r'^[a-zA-Z0-9]{30,}$').hasMatch(value)) {
      return const Error('用户ID要求至少为30个字符长度的纯字符串');
    }
    return _save(
      SponsorBlockPreference.userId,
      value,
      () =>
          state._copy(identity: (server: state.identity.server, userId: value)),
      refreshUser: true,
    );
  }

  Future<LoadingState<void>?> randomizeUserId() =>
      saveUserId(SponsorBlockPreferences.generateUserId());

  Future<LoadingState<void>?> resetServer() =>
      saveServer(SponsorBlockPreferences.defaultServer);

  Future<LoadingState<void>?> saveServer(String value) async {
    final server = value.trim();
    final uri = Uri.tryParse(server);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return const Error('请输入有效的 HTTP 或 HTTPS 服务器地址');
    }
    return _save(
      SponsorBlockPreference.server,
      server,
      () => state._copy(
        identity: (server: server, userId: state.identity.userId),
      ),
      refreshUptime: true,
      refreshUser: true,
    );
  }

  Future<LoadingState<void>?> saveColor(SegmentType category, Color? color) {
    final colors = List<Color>.unmodifiable([
      for (final entry in SegmentType.values)
        entry == category ? color ?? Color(category.colorValue) : state.colors[entry.index],
    ]);
    return _save(
      SponsorBlockPreference.colors,
      colors,
      () => state._copy(colors: colors),
    );
  }

  Future<LoadingState<void>?> saveBehavior(
    SegmentType category,
    SkipType behavior,
  ) {
    final behaviors = Map<SegmentType, SkipType>.unmodifiable({
      ...state.behaviors,
      category: behavior,
    });
    return _save(
      SponsorBlockPreference.behaviors,
      behaviors,
      () => state._copy(behaviors: behaviors),
    );
  }

  Future<LoadingState<void>?> _save(
    SponsorBlockPreference field,
    Object value,
    SponsorBlockSettings Function() update, {
    bool refreshUptime = false,
    bool refreshUser = false,
  }) async {
    final owner = _owner;
    if (!_isCurrent(owner) || _saving.containsKey(field)) return null;
    final operation = _saving[field] = Object();
    try {
      await SponsorBlockPreferences.save(field, value);
      if (!_isCurrent(owner)) return null;
      state = update();
      if (refreshUptime) unawaited(this.refreshUptime());
      if (refreshUser) unawaited(refreshUserInfo());
      return const Success(null);
    } catch (error, stackTrace) {
      logger.w('空降助手设置保存失败', error: error.runtimeType, stackTrace: stackTrace);
      return _isCurrent(owner)
          ? Error('设置保存失败，请重试', cause: error, stackTrace: stackTrace)
          : null;
    } finally {
      if (identical(_saving[field], operation)) _saving.remove(field);
    }
  }
}
