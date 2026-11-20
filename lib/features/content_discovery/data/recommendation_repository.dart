import 'package:dio/dio.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/model_rec_video_item.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

class RecommendationRepository {
  const RecommendationRepository();

  Future<LoadingState<List<BaseRcmdVideoItemModel>>> page({
    required Account account,
    required bool app,
    required int index,
    required int pageSize,
    required CancelToken cancelToken,
  }) => app
      ? VideoHttp.rcmdVideoListApp(
          account: account,
          freshIdx: index,
          cancelToken: cancelToken,
        )
      : VideoHttp.rcmdVideoList(
          account: account,
          freshIdx: index,
          ps: pageSize,
          cancelToken: cancelToken,
        );
}
