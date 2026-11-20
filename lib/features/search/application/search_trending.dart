import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/search/data/search_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/search/domain/suggestions/search_trending/data.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';

final searchTrendingProvider =
    NotifierProvider<SearchTrendingNotifier, LoadingState<SearchTrendingData>>(
      SearchTrendingNotifier.new,
      isAutoDispose: true,
    );

class SearchTrendingNotifier
    extends Notifier<LoadingState<SearchTrendingData>> {
  int _version = 0;
  bool _alive = true;
  @override
  LoadingState<SearchTrendingData> build() {
    ref.watch(recommendAccountProvider);
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      ++_version;
    });
    unawaited(refresh());
    return LoadingState.loading();
  }

  Future<void> refresh() async {
    final version = ++_version;
    final account = ref.read(recommendAccountProvider);
    LoadingState<SearchTrendingData> result;
    try {
      result = await const SearchRepository().trending(needsTop: true);
    } catch (error, stackTrace) {
      result = Error.fromException(error, stackTrace);
    }
    if (_alive &&
        version == _version &&
        identical(account, ref.read(recommendAccountProvider))) {
      state = result;
    }
  }
}
