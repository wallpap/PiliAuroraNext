import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/domain/reserve.dart';
import 'package:pili_aurora_next/features/community/domain/reserve_draft.dart';
import 'package:pili_aurora_next/http/dynamics.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

final reserveRepositoryProvider = Provider((ref) => const ReserveRepository());

class ReserveRepository {
  const ReserveRepository();
  Future<LoadingState<ReserveDraft>> load(Account account, int id) async =>
      switch (await DynamicsHttp.reserveInfo(sid: id, account: account)) {
        Success(:final response) => Success(
          ReserveDraft(
            title: response.title!,
            date: DateTime.fromMillisecondsSinceEpoch(
              response.livePlanStartTime! * 1000,
            ),
          ),
        ),
        Error error => error,
        _ => LoadingState.loading(),
      };

  Future<LoadingState<ReserveInfoData>> save(
    Account account,
    int? id,
    ReserveDraft draft,
  ) async {
    final timestamp = draft.date.millisecondsSinceEpoch ~/ 1000;
    final result = id == null
        ? await DynamicsHttp.createReserve(
            account: account,
            title: draft.title,
            subType: draft.subType,
            livePlanStartTime: timestamp,
          )
        : await DynamicsHttp.updateReserve(
            account: account,
            sid: id,
            title: draft.title,
            subType: draft.subType,
            livePlanStartTime: timestamp,
          );
    return switch (result) {
      Success(:final response) => Success(
        ReserveInfoData(
          id: response,
          title: draft.title,
          livePlanStartTime: timestamp,
        ),
      ),
      Error error => error,
      _ => LoadingState.loading(),
    };
  }
}
