import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pili_aurora_next/features/account/application/account_profile.dart';
import 'package:pili_aurora_next/features/account/data/profile_editor_repository.dart';
import 'package:pili_aurora_next/features/account/domain/profile_details.dart';
import 'package:pili_aurora_next/features/account/domain/profile_type.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

/// 每个编辑实例持有资料快照，查询和写入按账号对象及快照隔离。
class ProfileEditor extends ChangeNotifier {
  ProfileEditor() {
    Accounts.mainChanges.addListener(_accountChanged);
  }

  LoadingState<AccountMyInfoData> state = LoadingState.loading();
  Account account = Accounts.main;
  Object? _operation;
  int _query = 0;
  bool _disposed = false;
  bool get saving => _operation != null;
  bool needsVerification = false;
  ProfileType? _verificationType;
  int _verificationQuery = 0;

  bool ownsAccount(Account owner) =>
      !_disposed &&
      identical(owner, account) &&
      identical(owner, Accounts.main);

  bool owns(Account owner, AccountMyInfoData? source) =>
      ownsAccount(owner) &&
      source != null &&
      identical(source, state.dataOrNull);

  void _accountChanged() {
    if (identical(account, Accounts.main)) return;
    account = Accounts.main;
    _operation = null;
    needsVerification = false;
    _verificationType = null;
    unawaited(load());
  }

  Future<void> load() async {
    if (_disposed) return;
    final query = ++_query;
    final owner = account = Accounts.main;
    state = LoadingState.loading();
    notifyListeners();
    LoadingState<AccountMyInfoData> result;
    try {
      result = await ProfileEditorRepository.info(owner);
    } catch (error, stackTrace) {
      result = Error.fromException(error, stackTrace);
    }
    if (_disposed || query != _query || !identical(owner, Accounts.main)) {
      return;
    }
    if (result case Success(:final response)
        when needsVerification && query > _verificationQuery) {
      final verified = switch (_verificationType) {
        ProfileType.uname => response.name != null,
        ProfileType.sign => response.sign != null,
        ProfileType.sex => response.sex != null,
        ProfileType.birthday => response.birthday != null,
        null => response.face != null,
      };
      if (verified) {
        needsVerification = false;
        _verificationType = null;
      } else {
        result = Error(
          '资料尚不完整，暂时无法核对上次修改，请稍后刷新',
          cause: const FormatException('待核对字段缺失'),
          stackTrace: StackTrace.current,
        );
      }
    }
    state = result;
    notifyListeners();
    if (result case Success(:final response)) await _publish(owner, response);
  }

  Future<LoadingState<void>> update(ProfileType type, String value) async {
    final owner = account;
    final source = state.dataOrNull;
    if (saving) return const Error('资料正在提交，请稍候');
    if (needsVerification) return const Error('请先刷新资料核对上次修改结果');
    if (source == null || !owns(owner, source)) return const Error('请先刷新账号资料');
    if (type == ProfileType.sex && !const ['0', '1', '2'].contains(value)) {
      return const Error('请选择有效性别');
    }
    if (type == ProfileType.uname && value.trim().isEmpty) {
      return const Error('昵称不能为空');
    }
    final previous = switch (type) {
      ProfileType.uname => source.name,
      ProfileType.sign => source.sign ?? '',
      ProfileType.sex => source.sex?.toString(),
      ProfileType.birthday => source.birthday,
    };
    if (previous == value) return const Error('与当前资料相同');
    if (type == ProfileType.uname && (source.coins ?? 0) < 6) {
      return const Error('硬币不足');
    }
    final operation = _operation = Object();
    notifyListeners();
    try {
      final result = await ProfileEditorRepository.update(
        account: owner,
        type: type,
        value: value,
      );
      if (ownsAccount(owner) && result is UnknownResult) {
        // 刷新替换快照不能解除仍在途写入的待确认屏障。
        needsVerification = true;
        _verificationType = type;
        _verificationQuery = _query;
      }
      if (!owns(owner, source)) return result;
      if (result.isSuccess) {
        switch (type) {
          case ProfileType.uname:
            source
              ..name = value
              ..coins = math.max(0, (source.coins ?? 0) - 6);
          case ProfileType.sign:
            source.sign = value;
          case ProfileType.sex:
            source.sex = int.parse(value);
          case ProfileType.birthday:
            source.birthday = value;
        }
        notifyListeners();
        await _publish(owner, source);
      }
      return result;
    } catch (error, stackTrace) {
      logger.w('资料更新失败', error: error.runtimeType, stackTrace: stackTrace);
      return Error('资料更新失败，请重试', cause: error, stackTrace: stackTrace);
    } finally {
      if (!_disposed && identical(operation, _operation)) {
        _operation = null;
        notifyListeners();
      }
    }
  }

  Future<LoadingState<void>> avatar(String filePath) async {
    final owner = account;
    final source = state.dataOrNull;
    if (saving) return const Error('资料正在提交，请稍候');
    if (needsVerification) return const Error('请先刷新资料核对上次修改结果');
    if (source == null || !owns(owner, source)) return const Error('请先刷新账号资料');
    final operation = _operation = Object();
    notifyListeners();
    try {
      final result = await ProfileEditorRepository.avatar(
        account: owner,
        filePath: filePath,
      );
      if (ownsAccount(owner) && result is UnknownResult) {
        needsVerification = true;
        _verificationType = null;
        _verificationQuery = _query;
      }
      return result;
    } catch (error, stackTrace) {
      logger.w('头像更新失败', error: error.runtimeType, stackTrace: stackTrace);
      return Error('头像更新失败，请重试', cause: error, stackTrace: stackTrace);
    } finally {
      if (!_disposed && identical(operation, _operation)) {
        _operation = null;
        notifyListeners();
      }
    }
  }

  Future<void> _publish(Account owner, AccountMyInfoData info) async {
    if (!owns(owner, info)) return;
    try {
      final receipt = await AccountProfile.legacy.updateDisplay(
        owner,
        name: info.name,
        avatar: info.face,
      );
      if (receipt?.cacheError case final error?) {
        logger.w('账号资料本地同步失败', error: error.runtimeType);
      }
    } catch (error, stackTrace) {
      // 远端资料已经确认，次要缓存同步失败不能诱导用户重复付费改名。
      logger.w('账号资料本地同步失败', error: error.runtimeType, stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _query++;
    Accounts.mainChanges.removeListener(_accountChanged);
    super.dispose();
  }
}
