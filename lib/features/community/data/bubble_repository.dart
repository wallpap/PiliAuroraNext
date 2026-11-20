import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/domain/bubble_catalog.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/dynamics.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/community/domain/bubble/dyn_list.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

final bubbleRepositoryProvider = Provider((ref) => const BubbleRepository());

class BubbleRepository {
  const BubbleRepository();
  Future<LoadingState<DiscoveryPage<DynList, BubbleCatalog>>> page(
    Account account, {
    required String tribeId,
    String? categoryId,
    int? sortType,
    required int page,
    BubbleCatalog? previous,
  }) async {
    final result = await DynamicsHttp.bubble(
      account: account,
      tribeId: tribeId,
      categoryId: categoryId,
      sortType: sortType,
      page: page,
    );
    return switch (result) {
      Success(:final response) => Success(
        DiscoveryPage(
          response.content?.dynList ?? [],
          metadata: page == 1
              ? BubbleCatalog(
                  title: response.baseInfo?.tribeInfo?.title,
                  categories: response.category?.categoryList ?? [],
                  sort: response.sortInfo,
                )
              : previous ?? BubbleCatalog(),
          total: int.tryParse(response.content?.count ?? ''),
        ),
      ),
      Error error => error,
      _ => LoadingState.loading(),
    };
  }
}
