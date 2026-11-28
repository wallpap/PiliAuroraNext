import 'dart:collection';

import 'package:fixnum/fixnum.dart';
import 'package:pili_aurora_next/features/community/data/comments/comments_repository.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/community/domain/comments/interaction/data.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/content_discovery/application/blocked_authors.dart';

abstract final class CommentActions {
  static const _repository = CommentsRepository();
  static final _reacting = HashMap<Account, Set<(Int64, Int64)>>.identity();

  static Future<LoadingState<ReplyInteractData>> interactionSettings(
    Account account,
    int oid,
    int type,
  ) => _repository.interactionSettings(account, oid, type);

  static Future<LoadingState<void>> report(
    Account account,
    CommentReply reply, {
    required int reason,
    String? description,
    required bool block,
  }) async {
    final result = await _repository.report(
      account,
      reply,
      reason: reason,
      description: description,
      block: block,
    );
    final mid = reply.authorMid;
    if (result.isSuccess &&
        block &&
        mid > Int64.ZERO &&
        identical(account, Accounts.main)) {
      BlockedAuthors.setBlocked(mid.toInt(), true);
    }
    return result;
  }

  static Future<LoadingState<void>> delete(
    Account account,
    CommentReply reply,
  ) {
    if (!identical(Accounts.main, account)) {
      return Future.value(const Error('账号已切换，请重新打开评论菜单'));
    }
    return _repository.delete(account, reply);
  }

  static Future<LoadingState<Int64>?> react(
    Account account,
    CommentReply reply, {
    required bool like,
    required bool Function() isCurrent,
  }) async {
    if (!identical(Accounts.main, account)) return null;
    final target = (reply.oid, reply.id);
    final pending = _reacting.putIfAbsent(account, () => {});
    if (!pending.add(target)) return null;
    final before = reply.replyControl.action;
    final selected = like ? Int64.ONE : Int64.TWO;
    final next = before == selected ? Int64.ZERO : selected;
    try {
      final result = await _repository.react(
        account,
        reply,
        like: like,
        remove: next == Int64.ZERO,
      );
      if (!isCurrent()) return null;
      if (result case Error error) return error;
      if (!result.isSuccess || reply.replyControl.action != before) return null;
      if (before == Int64.ONE && reply.like > Int64.ZERO) {
        reply.like -= Int64.ONE;
      }
      if (next == Int64.ONE) reply.like += Int64.ONE;
      reply.replyControl.action = next;
      return Success(next);
    } finally {
      pending.remove(target);
      if (pending.isEmpty) _reacting.remove(account);
    }
  }
}
