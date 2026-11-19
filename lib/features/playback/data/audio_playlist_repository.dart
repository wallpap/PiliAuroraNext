import 'package:fixnum/fixnum.dart';
import 'package:pili_aurora_next/generated/bilibili/app/listener/v1.pb.dart';
import 'package:pili_aurora_next/grpc/audio.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef AudioPlaylistAnchor = ({
  Int64 id,
  Int64 oid,
  List<Int64> subIds,
  int itemType,
  PlaylistSource source,
  Int64? extraId,
});

typedef AudioPlaylistPage = ({
  List<DetailItem> items,
  String? previous,
  String? next,
});

abstract final class AudioPlaylistRepository {
  static Future<LoadingState<AudioPlaylistPage>> fetch(
    AudioPlaylistAnchor anchor,
    Account account,
    ListOrder order, {
    String? cursor,
  }) async {
    final initial = cursor == null;
    final result = await AudioGrpc.audioPlayList(
      account: account,
      id: anchor.id,
      oid: initial ? anchor.oid : null,
      subId: initial ? anchor.subIds : null,
      itemType: initial ? anchor.itemType : null,
      from: initial ? anchor.source : null,
      extraId: anchor.extraId,
      order: order,
      next: cursor,
    );
    return switch (result) {
      Success(:final response) => Success((
        items: response.list,
        previous: _cursor(response.reachStart, response.paginationReply.prev),
        next: _cursor(response.reachEnd, response.paginationReply.next),
      )),
      Error() => result,
      Loading() => const Error('播放列表尚未加载完成，请重试'),
    };
  }

  static String? _cursor(bool ended, String cursor) =>
      ended || cursor.isEmpty ? null : cursor;
}
