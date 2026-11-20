import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/account/data/account_log_repository.dart';
import 'package:pili_aurora_next/features/account/domain/account_log.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';

final logTableProvider = FutureProvider.autoDispose
    .family<List<LogRow>, LogType>(
      (ref, type) async {
        final account = ref.watch(mainAccountProvider);
        if (!account.isLogin) throw const Error('账号未登录');
        try {
          return (await AccountLogRepository.load(account, type)).data;
        } on Error {
          rethrow;
        } catch (_) {
          throw const Error('加载失败，请重试');
        }
      },
      retry: (_, _) => null,
    );
