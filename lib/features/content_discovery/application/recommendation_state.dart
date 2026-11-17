import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/model_rec_video_item.dart';

/// 列表结构与调度快照；单张卡片揭示通过独立订阅交付。
class RecommendationState {
  RecommendationState({
    LoadingState<List<BaseRcmdVideoItemModel>>? loading,
    this.historyStart,
    this.error,
    this.loadingMore = false,
    this.stopped = false,
    this.source,
  }) : loading = loading ?? LoadingState.loading();
  final LoadingState<List<BaseRcmdVideoItemModel>> loading;
  final int? historyStart;
  final String? error;
  final bool loadingMore;
  final bool stopped;
  final Object? source;
  bool get canLoadMore =>
      !stopped && !loadingMore && loading.dataOrNull != null;
}
