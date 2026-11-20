import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/http/live.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/live/live_contribution_rank_type.dart';
import 'package:pili_aurora_next/models/remote/live/live_contribution_rank/item.dart';
import 'package:pili_aurora_next/models/remote/live/live_guard_top_list/data.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';

typedef LiveRankingRoom = ({Object scope, Object room, Object anchor});
typedef LiveContributionQuery = (LiveRankingRoom, LiveContributionRankType);

final liveContributionProvider = FutureProvider.autoDispose
    .family<
      LoadingState<List<LiveContributionRankItem>>,
      LiveContributionQuery
    >(
      (ref, query) async {
        final account = ref.watch(mainAccountProvider);
        final (room, type) = query;
        final result = await LiveHttp.liveContributionRank(
          account: account,
          ruid: room.anchor,
          roomId: room.room,
          page: 1,
          type: type,
        );
        return switch (result) {
          Success(:final response) => Success(
            List.unmodifiable(response.item ?? const []),
          ),
          Error() => result,
          Loading() => LoadingState.loading(),
        };
      },
    );

final liveGuardRankingProvider = FutureProvider.autoDispose
    .family<LoadingState<LiveGuardTopListData>, LiveRankingRoom>((ref, room) {
      final account = ref.watch(mainAccountProvider);
      return LiveHttp.liveGuardTopList(
        account: account,
        roomId: room.room,
        ruid: room.anchor,
      );
    });

LoadingState<T> liveRankingResult<T>(AsyncValue<LoadingState<T>> state) =>
    state.when(
      data: (result) => result,
      error: Error.fromException,
      loading: LoadingState.loading,
    );
