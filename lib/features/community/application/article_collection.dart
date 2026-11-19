import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/article_repository.dart';
import 'package:pili_aurora_next/features/community/domain/article_collection/data.dart';
import 'package:pili_aurora_next/services/account_providers.dart';

final articleCollectionProvider = FutureProvider.autoDispose
    .family<ArticleCollection, String>((ref, id) async {
      final account = ref.watch(mainAccountProvider);
      return (await ArticleRepository.collection(account, id)).data;
    }, retry: (_, _) => null);
