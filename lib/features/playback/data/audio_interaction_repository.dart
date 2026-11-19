import 'package:pili_aurora_next/features/playback/domain/audio_track.dart';
import 'package:pili_aurora_next/generated/bilibili/app/listener/v1.pbenum.dart';
import 'package:pili_aurora_next/grpc/audio.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef AudioTripleReceipt = ({bool liked, bool coined, bool favored});

abstract final class AudioInteractionRepository {
  static Future<LoadingState<String>> like(
    Account account,
    AudioTarget target,
    bool value,
  ) async {
    final result = await AudioGrpc.audioThumbUp(
      account: account,
      oid: target.oid,
      subId: target.parts,
      itemType: target.type,
      type: value
          ? ThumbUpReq_ThumbType.LIKE
          : ThumbUpReq_ThumbType.CANCEL_LIKE,
    );
    return switch (result) {
      Success(:final response) => Success(response.message),
      Error() => result,
      Loading() => LoadingState.loading(),
    };
  }

  static Future<LoadingState<AudioTripleReceipt>> triple(
    Account account,
    AudioTarget target,
  ) async {
    final result = await AudioGrpc.audioTripleLike(
      account: account,
      oid: target.oid,
      subId: target.parts,
      itemType: target.type,
    );
    return switch (result) {
      Success(:final response) => Success((
        liked: response.thumbOk,
        coined: response.coinOk,
        favored: response.favOk,
      )),
      Error() => result,
      Loading() => LoadingState.loading(),
    };
  }

  static Future<LoadingState<void>> coin(
    Account account,
    AudioTarget target,
    int amount,
    bool withLike,
  ) async {
    final result = await AudioGrpc.audioCoinAdd(
      account: account,
      oid: target.oid,
      subId: target.parts,
      itemType: target.type,
      num: amount,
      thumbUp: withLike,
    );
    return switch (result) {
      Success() => const Success(null),
      Error() => result,
      Loading() => LoadingState.loading(),
    };
  }
}
