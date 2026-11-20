import 'package:pili_aurora_next/common/scroll_or_refresh.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_page_handle.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/recommendation_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';

LoadingState<List<Object?>>? feedLoading(ScrollOrRefreshMixin? page) =>
    switch (page) {
      RecommendationPageHandle(:final snapshot) => snapshot.loading,
      DiscoveryPageHandle(:final snapshot) => snapshot?.loading,
      _ => null,
    };
