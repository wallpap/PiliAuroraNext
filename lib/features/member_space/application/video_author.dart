import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/member_space/data/space_repository.dart';
import 'package:pili_aurora_next/features/member_space/domain/video_author.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef VideoAuthorQuery = ({Object owner, int mid});

final videoAuthorProvider = NotifierProvider.autoDispose
    .family<VideoAuthor, VideoAuthorState, VideoAuthorQuery>(VideoAuthor.new);

class VideoAuthorState {
  const VideoAuthorState({
    required this.account,
    required this.source,
    required this.profile,
    this.followed = false,
    this.followers,
    this.following,
    this.likes,
  });

  final Account account;
  final Object source;
  final LoadingState<VideoAuthorInfo> profile;
  final bool followed;
  final int? followers, following, likes;
}

class VideoAuthor extends Notifier<VideoAuthorState> {
  VideoAuthor(this.query);
  final VideoAuthorQuery query;

  VideoAuthorState _loading(Account account) => VideoAuthorState(
    account: account,
    source: Object(),
    profile: LoadingState.loading(),
  );

  @override
  VideoAuthorState build() {
    final snapshot = _loading(ref.watch(mainAccountProvider));
    scheduleMicrotask(() => unawaited(_load(snapshot)));
    return snapshot;
  }

  bool owns(VideoAuthorState snapshot) =>
      ref.mounted &&
      identical(snapshot.account, ref.read(mainAccountProvider)) &&
      identical(snapshot.source, state.source);

  Future<void> refresh() {
    final snapshot = _loading(ref.read(mainAccountProvider));
    state = snapshot;
    return _load(snapshot);
  }

  Future<void> _load(VideoAuthorState snapshot) async {
    if (!owns(snapshot)) return;
    final repository = ref.read(spaceRepositoryProvider);
    final account = snapshot.account;
    final result = await repository.videoAuthor(account, query.mid);
    if (!owns(snapshot)) return;
    _publish(profile: result, followed: result.dataOrNull?.followed);
    if (!result.isSuccess) return;

    Future<void> relations() async {
      final result = await repository.authorRelations(account, query.mid);
      if (!owns(snapshot) || result is! Success<Map<String, dynamic>>) return;
      final followers = result.response['follower'];
      final following = result.response['following'];
      _publish(
        followers: followers is int ? followers : null,
        following: following is int ? following : null,
      );
    }

    Future<void> views() async {
      final result = await repository.authorViews(account, query.mid);
      if (!owns(snapshot) || result is! Success<Map<String, dynamic>>) return;
      final likes = result.response['likes'];
      _publish(likes: likes is int ? likes : null);
    }

    await Future.wait([relations(), if (account.isLogin) views()]);
  }

  void setFollowed(VideoAuthorState snapshot, bool followed) {
    if (owns(snapshot)) _publish(followed: followed);
  }

  void _publish({
    LoadingState<VideoAuthorInfo>? profile,
    bool? followed,
    int? followers,
    int? following,
    int? likes,
  }) {
    final before = state;
    state = VideoAuthorState(
      account: before.account,
      source: before.source,
      profile: profile ?? before.profile,
      followed: followed ?? before.followed,
      followers: followers ?? before.followers,
      following: following ?? before.following,
      likes: likes ?? before.likes,
    );
  }
}
