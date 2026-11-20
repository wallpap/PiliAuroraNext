import 'dart:async';
import 'dart:math' as math;

import 'package:pili_aurora_next/features/playback/domain/danmaku_metadata.dart';
import 'package:pili_aurora_next/http/danmaku.dart';
import 'package:pili_aurora_next/features/playback/data/danmaku_block_repository.dart';
import 'package:pili_aurora_next/features/playback/data/danmaku_rule_cache.dart';
import 'package:pili_aurora_next/features/playback/domain/danmaku_block_type.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/playback/domain/danmaku_rule.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';

typedef DanmakuBlockRules = ({
  RuleFilter Function() read,
  void Function(RuleFilter) publish,
});

class VideoDanmakuInteractions {
  VideoDanmakuInteractions(this._cid, {required this._mediaIsCurrent});

  final int _cid;
  final bool Function() _mediaIsCurrent;
  final _account = Accounts.main;

  bool get isLogin => _account.isLogin;
  bool get isCurrent => identical(_account, Accounts.main) && _mediaIsCurrent();
  static const _loginRequired = Error('请先登录');
  static final _likeRevisions =
      Expando<Map<(int, int), _DanmakuLikeRevision>>();
  static final _unconfirmedLikes = Expando<({Object account, int cid})>();

  Future<Result> _withLikeRevision<Result>(
    VideoDanmaku entry,
    Future<Result> Function(_DanmakuLikeRevision) run,
  ) async {
    final revisions = _likeRevisions[_account] ??= {};
    final key = (_cid, entry.id);
    final revision = revisions.putIfAbsent(key, _DanmakuLikeRevision.new);
    revision.active++;
    try {
      return await run(revision);
    } finally {
      if (--revision.active == 0) revisions.remove(key);
    }
  }

  Future<LoadingState<void>?> refreshLike(VideoDanmaku entry) async {
    if (!isCurrent) return null;
    if (!isLogin) {
      entry.isLike = false;
      return const Success(null);
    }
    return _withLikeRevision(entry, (revision) async {
      while (isCurrent) {
        if (revision.pending case final pending?) {
          await pending.future;
          continue;
        }
        final requestedAt = revision.number;
        final result = await DanmakuHttp.likeStats(
          cid: _cid,
          id: entry.id,
          account: _account,
        );
        if (!isCurrent) return null;
        if (requestedAt != revision.number) continue;
        if (result case Success(:final response)) {
          _unconfirmedLikes[entry] = null;
          entry
            ..isLike = response.isLike
            ..like = response.likes;
          return const Success(null);
        }
        return result is Error ? result : null;
      }
      return null;
    });
  }

  Future<LoadingState<String?>?> toggleLike(VideoDanmaku entry) async {
    if (!isCurrent) return null;
    if (!isLogin) return _loginRequired;
    final unconfirmed = _unconfirmedLikes[entry];
    if (unconfirmed != null &&
        identical(unconfirmed.account, _account) &&
        unconfirmed.cid == _cid) {
      return const UnknownResult();
    }
    return _withLikeRevision(entry, (revision) => _toggleLike(entry, revision));
  }

  Future<LoadingState<String?>?> _toggleLike(
    VideoDanmaku entry,
    _DanmakuLikeRevision revision,
  ) async {
    if (revision.pending != null) return null;
    final pending = revision.pending = Completer<void>();
    revision.number++;
    final liked = !entry.isLike;
    try {
      final result = await DanmakuHttp.danmakuLike(
        account: _account,
        isLike: liked,
        cid: _cid,
        id: entry.id,
      );
      if (!isCurrent) {
        _unconfirmedLikes[entry] = (account: _account, cid: _cid);
        return null;
      }
      if (result.isSuccess) {
        entry
          ..isLike = liked
          ..like = math.max(0, entry.like + (liked ? 1 : -1));
        return Success('${liked ? '' : '取消'}点赞成功');
      }
      if (result case Error(:final code)) {
        if (code == 65006 || code == 65004) {
          entry.isLike = code == 65006;
          return const Success(null);
        }
        if (result is UnknownResult) {
          _unconfirmedLikes[entry] = (account: _account, cid: _cid);
        }
        return result;
      }
      return null;
    } finally {
      revision.pending = null;
      pending.complete();
    }
  }

  Future<LoadingState<String?>?> recall(int id) async {
    if (!isCurrent) return null;
    if (!isLogin) return _loginRequired;
    final result = await DanmakuHttp.danmakuRecall(
      account: _account,
      cid: _cid,
      id: id,
    );
    return isCurrent ? result : null;
  }

  Future<LoadingState<String?>?> report(
    VideoDanmaku entry, {
    required int reason,
    required String? description,
    DanmakuBlockRules? blockRules,
  }) async {
    if (!isCurrent) return null;
    if (!isLogin) return _loginRequired;
    final result = await DanmakuHttp.danmakuReport(
      account: _account,
      reason: reason,
      cid: _cid,
      id: entry.id,
      content: description,
    );
    if (!isCurrent) return null;
    if (!result.isSuccess) return result is Error ? result : null;
    if (blockRules == null) return const Success(null);
    try {
      final filter = blockRules.read();
      if (filter.dmUid.add(entry.mid)) {
        filter.count++;
        blockRules.publish(filter);
        await DanmakuRuleCache.save(filter);
      }
      if (!isCurrent) return null;
      final blockResult = await DanmakuBlockRepository.danmakuFilterAdd(
        account: _account,
        filter: entry.mid,
        type: DmBlockType.uid.index,
      );
      if (!isCurrent) return null;
      if (blockResult is Error) {
        return Success('举报成功；屏蔽规则同步：$blockResult');
      }
    } catch (error, stackTrace) {
      final failure = Error.fromException(error, stackTrace);
      if (!isCurrent) return null;
      return Success('举报成功；本地屏蔽保存失败：$failure');
    }
    return const Success(null);
  }

  Future<LoadingState<int?>?> send({
    required String bvid,
    required int progress,
    required String message,
    required int mode,
    required int fontSize,
    required int? color,
    required bool colorful,
  }) async {
    if (!isCurrent) return null;
    final result = await DanmakuHttp.shootDanmaku(
      account: _account,
      oid: _cid,
      bvid: bvid,
      progress: progress,
      msg: message,
      mode: mode,
      fontSize: fontSize,
      color: color,
      colorful: colorful,
    );
    if (!isCurrent) return null;
    return switch (result) {
      Success(:final response) => Success(response.dmid),
      Error() => result,
      _ => null,
    };
  }
}

class _DanmakuLikeRevision {
  int active = 0;
  int number = 0;
  Completer<void>? pending;
}
