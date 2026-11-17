import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/model_hot_video_item.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final hotRepositoryProvider = Provider((ref) => const HotRepository());

class HotRepository {
  const HotRepository();
  Future<LoadingState<DiscoveryPage<HotVideoItemModel, void>>> fetch(
    Account account,
    int page,
  ) async {
    final result = await VideoHttp.hotVideoList(
      pn: page,
      ps: 20,
      account: account,
    );
    return switch (result) {
      Success(:final response) => Success(
        DiscoveryPage(response, metadata: null),
      ),
      Error error => error,
      Loading() => LoadingState.loading(),
    };
  }
}
