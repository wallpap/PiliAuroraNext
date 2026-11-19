import 'package:pili_aurora_next/features/community/data/comments/comment_protocol.dart';
import 'package:pili_aurora_next/features/community/data/comments/comment_visibility_repository.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/android/android_helper.dart';

enum CommentVisibility { public, directLinkOnly, ownViewOnly, missing }

abstract final class CommentVisibilityCheck {
  static void launchAndroidAssistant(
    Account account,
    CommentReply reply,
    Object sourceId,
  ) {
    try {
      final cookie = account.cookieJar
          .toJson()
          .entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(';');
      PiliAndroidHelper.biliSendCommAntifraud(
        0,
        reply.oid.toInt(),
        reply.type.toInt(),
        reply.id.toInt(),
        reply.root.toInt(),
        reply.parent.toInt(),
        reply.ctime.toInt(),
        reply.content.message,
        commentPicturesForAntifraud(reply),
        sourceId.toString(),
        reply.mid.toInt(),
        cookie,
      );
    } catch (error, stackTrace) {
      logger.w('调用评论检查助手失败', error: error.runtimeType, stackTrace: stackTrace);
    }
  }

  static Future<LoadingState<CommentVisibility>?> inspect(
    Account account,
    CommentReply reply, {
    required bool Function() isCurrent,
  }) async {
    final oid = reply.oid.toInt();
    final type = reply.type.toInt();
    final id = reply.id.toInt();
    final root = reply.root.toInt();

    if (!isCurrent()) return null;
    Future<LoadingState<VisibilityPage>> thread(
      bool isLogin,
      int page,
    ) => CommentVisibilityRepository.thread(
      account: account,
      isLogin: isLogin,
      oid: oid,
      type: type,
      root: root == 0 ? id : root,
      page: page,
    );
    Error failed(Error error) => Error('评论检查失败：$error', cause: error);

    if (root == 0) {
      final latest = await CommentVisibilityRepository.inPublicList(
        oid: oid,
        type: type,
        id: id,
      );
      if (!isCurrent()) return null;
      if (latest case Error error) {
        return Error('获取评论主列表时发生错误：$error', cause: error);
      }
      if (latest.dataOrNull == true) {
        return const Success(CommentVisibility.public);
      }
      final own = await thread(true, 1);
      if (!isCurrent()) return null;
      if (own case Error error) {
        return error.code == 12022
            ? const Success(CommentVisibility.missing)
            : failed(error);
      }
      final anonymous = await thread(false, 1);
      if (!isCurrent()) return null;
      if (anonymous case Error error) {
        return error.code == 12022
            ? const Success(CommentVisibility.ownViewOnly)
            : failed(error);
      }
      return const Success(CommentVisibility.directLinkOnly);
    }

    Future<LoadingState<bool>?> contains(bool isLogin) async {
      final seen = <int?>{};
      for (var page = 1; page <= 100; page++) {
        final result = await thread(isLogin, page);
        if (!isCurrent()) return null;
        if (result case Error error) {
          return error.code == 12022 ? const Success(false) : error;
        }
        final data = result.data;
        if (data.ids.isEmpty) return const Success(false);
        if (data.ids.contains(id)) return const Success(true);
        final before = seen.length;
        seen.addAll(data.ids);
        if (seen.length == before || seen.contains(null)) {
          return const Error('评论列表未能继续加载，暂时无法确认评论状态');
        }
        final (:count, :size, ids: _) = data;
        if (count != null && size != null && size > 0 && page * size >= count) {
          return const Success(false);
        }
      }
      return const Error('评论列表超出检查上限，请稍后重试');
    }

    final anonymous = await contains(false);
    if (!isCurrent() || anonymous == null) return null;
    if (anonymous case Error error) return failed(error);
    if (anonymous.data) return const Success(CommentVisibility.public);

    final own = await contains(true);
    if (!isCurrent() || own == null) return null;
    if (own case Error error) return failed(error);
    return Success(
      own.data ? CommentVisibility.ownViewOnly : CommentVisibility.missing,
    );
  }
}
