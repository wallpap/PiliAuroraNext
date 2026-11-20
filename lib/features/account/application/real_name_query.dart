import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/features/account/domain/real_name/data.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/user.dart';

Future<LoadingState<UserRealNameData>> queryRealName(
  String mid,
  AccountScope scope,
) => UserHttp.getUserRealName(mid, account: scope.account);
