import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/member_space/data/upower_rank_repository.dart';
import 'package:pili_aurora_next/features/member_space/domain/upower_ranking.dart';
import 'package:pili_aurora_next/services/account_providers.dart';

typedef UpowerRankQuery = ({String mid, int? privilege, Object owner});

final upowerRankingProvider = FutureProvider.autoDispose
    .family<UpowerRanking, UpowerRankQuery>((ref, query) async {
      final account = ref.watch(mainAccountProvider);
      return (await UpowerRankRepository.load(
        account,
        query.mid,
        privilege: query.privilege,
      )).data;
    }, retry: (_, _) => null);
