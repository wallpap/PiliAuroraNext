import 'dart:math' show max;

import 'package:pili_aurora_next/features/community/application/dynamics_actions.dart';
import 'package:pili_aurora_next/features/community/data/article_repository.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/image_preview_type.dart';
import 'package:pili_aurora_next/features/community/domain/dynamics/article_content_model.dart'
    show ArticleContentModel;
import 'package:pili_aurora_next/features/community/domain/dynamics/result.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/avatar.dart';
import 'package:pili_aurora_next/features/community/domain/article/article_view/data.dart';
import 'package:pili_aurora_next/features/community/application/content_page_detail.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/app_scheme.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/url_utils.dart';

typedef _ArticleContext = ({
  Account account,
  int version,
  String id,
  String type,
});

class ArticleController extends ContentPageDetail {
  ArticleController(
    this._dynamicsActions, {
    this.id = '',
    this.type = '',
    super.onFeedback,
  });

  final DynamicsActions _dynamicsActions;
  String id;
  String type;

  String get url => type == 'read'
      ? 'https://www.bilibili.com/read/cv$id'
      : 'https://www.bilibili.com/opus/$id';
  int commentId = 0;
  @override
  int get oid => commentId;
  int commentType = 12;
  @override
  int get replyType => commentType;
  final summary = Summary();

  final topIndex = DetailValue(0);
  void setTopIndex(int value) {
    if (!isClosed) topIndex.value = value;
  }

  @override
  Object get sourceId => commentType == 12 ? 'cv$commentId' : id;

  bool _contentLoading = false;
  bool _initialized = false;
  int _contentVersion = 0;
  int _infoVersion = 0;
  Object? _favoriteOperation;
  Object? _likeOperation;
  final isLoaded = DetailValue(false);
  DynamicItemModel? opusData; // 标题信息从summary获取, 动态没有favorite
  ArticleViewData? articleData;
  final stats = DetailValue<ModuleStatModel?>(null);

  List<ArticleContentModel>? get opus =>
      opusData?.modules.moduleContent ?? articleData?.opus?.content;

  List<SourceModel>? _images;
  List<SourceModel> images() => _images ??= [
    for (final paragraph in opus ?? <ArticleContentModel>[])
      if (paragraph.paraType == 2)
        if (paragraph.pic?.pics?.firstOrNull?.url case final url?
            when url.isNotEmpty)
          SourceModel(url: url),
  ];

  _ArticleContext get _context => (
    account: Accounts.main,
    version: _contentVersion,
    id: id,
    type: type,
  );

  bool _owns(_ArticleContext context) =>
      !isClosed &&
      identical(context.account, Accounts.main) &&
      context.version == _contentVersion &&
      context.id == id &&
      context.type == type;

  @override
  void open() {
    Accounts.mainChanges.addListener(onAccountChanged);

    // to opus
    if (type == 'read') {
      final originalId = id;
      UrlUtils.parseRedirectUrl('https://www.bilibili.com/read/cv$id/').then((
        url,
      ) {
        if (isClosed || id != originalId || type != 'read') return;
        if (url != null) {
          final opusId = PiliScheme.uriDigitRegExp.firstMatch(url)?.group(1);
          if (opusId != null) {
            id = opusId;
            type = 'opus';
          }
        }
        init();
      });
    } else {
      init();
    }
  }

  void onAccountChanged() {
    count = -1;
    _contentVersion++;
    _infoVersion++;
    _contentLoading = false;
    _favoriteOperation = _likeOperation = null;
    isLoaded.value = false;
    opusData = null;
    articleData = null;
    _images = null;
    stats.value = null;
    summary
      ..author = null
      ..title = null
      ..cover = null;
    showTitle.value = false;
    commentSource.value = LoadingState.loading();
    if (_initialized) _queryContent();
  }

  void init() {
    if (isClosed) return;
    commentType = type == 'picture' ? 11 : 12;
    _initialized = true;
    if ((int.tryParse(id) ?? 0) <= 0) {
      commentSource.value = const Error('文章地址无效，请重新打开');
      return;
    }
    _queryContent();
  }

  Future<bool> queryOpus(String opusId) async {
    final context = _context;
    final res = await ArticleRepository.opus(context.account, opusId);
    if (!_owns(context)) return false;
    if (res case Success(:final response)) {
      //fallback
      if (response.fallback?.id != null) {
        final articleId = int.tryParse(response.fallback!.id!);
        if (articleId == null || articleId <= 0) {
          commentSource.value = const Error('文章缺少有效编号，请重试');
          return false;
        }
        id = response.fallback!.id!;
        type = 'read';
        commentId = articleId;
        commentType = 12;
        return queryRead(commentId);
      }
      if (response.idStr != null && response.idStr.toString() != opusId) {
        commentSource.value = const Error('文章与请求目标不符，请重试');
        return false;
      }
      opusData = response;
      articleData = null;
      _images = null;
      commentType = response.basic!.commentType!;
      commentId = int.parse(response.basic!.commentIdStr!);
      if (showDynActionBar) {
        if (response.modules.moduleStat != null) {
          stats.value = response.modules.moduleStat;
        } else {
          getArticleInfo();
        }
      }
      summary
        ..author ??= response.modules.moduleAuthor
        ..title ??= response.modules.moduleTag?.text;
      return true;
    } else {
      commentSource.value = res as Error;
      return false;
    }
  }

  Future<bool> queryRead(int cvid) async {
    final context = _context;
    final res = await ArticleRepository.read(context.account, cvid);
    if (!_owns(context)) return false;
    if (res case Success(:final response)) {
      if (response.id != null && response.id != cvid) {
        commentSource.value = const Error('文章与请求目标不符，请重试');
        return false;
      }
      articleData = response;
      opusData = null;
      _images = null;
      summary
        ..author ??= response.author
        ..title ??= response.title
        ..cover ??= response.originImageUrls?.firstOrNull;

      if (showDynActionBar) {
        getArticleInfo();
      }
      return true;
    } else {
      commentSource.value = res as Error;
      return false;
    }
  }

  // stats
  Future<bool> getArticleInfo([bool isGetCover = false]) async {
    final context = _context;
    final articleId = commentId;
    final version = ++_infoVersion;
    final res = await ArticleRepository.stats(context.account, articleId);
    if (!_owns(context) || version != _infoVersion || articleId != commentId) {
      return false;
    }
    if (res case Success(:final response)) {
      summary
        ..cover ??= response.originImageUrls?.firstOrNull
        ..title ??= response.title;

      stats.value ??= ModuleStatModel(
        comment: DynamicStat(count: response.stats?.reply),
        forward: DynamicStat(count: response.stats?.share),
        like: DynamicStat(
          count: response.stats?.like,
          status: response.like,
        ),
        favorite: DynamicStat(
          count: response.stats?.favorite,
          status: response.favorite,
        ),
      );
      return true;
    }
    if (isGetCover) {
      onFeedback?.call(res.toString());
    }
    return false;
  }

  // 请求动态内容
  Future<void> _queryContent() async {
    if (isClosed || _contentLoading) return;
    _contentLoading = true;
    final version = ++_contentVersion;
    final account = Accounts.main;
    final heartbeat = Accounts.heartbeat;
    try {
      final bool loaded;
      if (type != 'read') {
        loaded = await queryOpus(id);
      } else {
        final articleId = int.tryParse(id);
        if (articleId == null || articleId <= 0) {
          commentSource.value = const Error('文章地址无效，请重新打开');
          return;
        }
        commentId = articleId;
        commentType = 12;
        loaded = await queryRead(commentId);
      }
      if (isClosed ||
          version != _contentVersion ||
          !identical(account, Accounts.main)) {
        return;
      }
      isLoaded.value = loaded;
      if (loaded) {
        showComments();
        if (heartbeat.isLogin &&
            identical(heartbeat, Accounts.heartbeat) &&
            !Pref.historyPause) {
          ArticleRepository.recordView(heartbeat, commentId);
        }
      }
    } finally {
      if (version == _contentVersion) _contentLoading = false;
    }
  }

  Future<void> onFav() async {
    if (isClosed || _favoriteOperation != null) return;
    final context = _context;
    if (!context.account.isLogin) {
      onFeedback?.call('账号未登录');
      return;
    }
    final favorite = stats.value?.favorite;
    if (favorite == null) return;
    final articleId = commentId;
    final isFav = favorite.status ?? false;
    final operation = _favoriteOperation = Object();
    try {
      final res = await FavoriteLibrary.legacy.article(
        context.account,
        articleId: articleId,
        opusId: context.type == 'read' ? null : context.id,
        remove: isFav,
      );
      if (!_owns(context) ||
          articleId != commentId ||
          !identical(favorite, stats.value?.favorite)) {
        return;
      }
      if (res.isSuccess) {
        _infoVersion++;
        favorite.status = !isFav;
        if (favorite.count case final count?) {
          favorite.count = max(0, count + (isFav ? -1 : 1));
        }
        stats.refresh();
        onFeedback?.call('${isFav ? '取消' : ''}收藏成功');
      } else {
        onFeedback?.call(res.toString());
      }
    } finally {
      if (identical(_favoriteOperation, operation)) _favoriteOperation = null;
    }
  }

  Future<void> onLike() async {
    if (isClosed || _likeOperation != null) return;
    final context = _context;
    if (!context.account.isLogin) {
      onFeedback?.call('账号未登录');
      return;
    }
    final like = stats.value?.like;
    if (like == null) return;
    final dynamicId = (opusData?.idStr ?? articleData?.dynIdStr)?.toString();
    if ((int.tryParse(dynamicId ?? '') ?? 0) <= 0) {
      onFeedback?.call('暂未获取到文章动态编号，请刷新后重试');
      return;
    }
    final isLike = like.status ?? false;
    final pending = _dynamicsActions.setLike(
      context.account,
      dynamicId!,
      !isLike,
    );
    if (pending == null) return;
    final operation = _likeOperation = Object();
    try {
      final res = await pending;
      if (!_owns(context) || !identical(like, stats.value?.like)) return;
      if (res.isSuccess) {
        _infoVersion++;
        like.status = !isLike;
        if (like.count case final count?) {
          like.count = max(0, count + (isLike ? -1 : 1));
        }
        stats.refresh();
        onFeedback?.call(!isLike ? '点赞成功' : '取消赞');
      } else {
        onFeedback?.call(res.toString());
      }
    } finally {
      if (identical(_likeOperation, operation)) _likeOperation = null;
    }
  }

  @override
  Future<void> onReload() {
    if (!isLoaded.value) {
      commentSource.value = LoadingState.loading();
      return _queryContent();
    }
    return Future.value();
  }

  @override
  void close() {
    if (isClosed) return;
    Accounts.mainChanges.removeListener(onAccountChanged);
    _contentVersion++;
    _infoVersion++;
    topIndex.dispose();
    isLoaded.dispose();
    stats.dispose();
    super.close();
  }
}

class Summary {
  Avatar? author;
  String? title;
  String? cover;

  Summary({this.author, this.title, this.cover});
}
