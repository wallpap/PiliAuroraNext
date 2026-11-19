import 'package:fixnum/fixnum.dart';
import 'package:pili_aurora_next/features/playback/domain/audio_track.dart';
import 'package:pili_aurora_next/generated/bilibili/app/listener/v1.pb.dart';
import 'package:pili_aurora_next/grpc/audio.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef AudioPlaylistAnchor = ({
  Int64 id,
  Int64 oid,
  List<Int64> subIds,
  int itemType,
  AudioPlaylistSource source,
  Int64? extraId,
});

typedef AudioPlaylistPage = ({
  List<AudioTrack> items,
  String? previous,
  String? next,
});

abstract final class AudioPlaylistRepository {
  static Future<LoadingState<AudioPlaylistPage>> fetch(
    AudioPlaylistAnchor anchor,
    Account account,
    AudioPlaylistOrder order, {
    String? cursor,
  }) async {
    final initial = cursor == null;
    final result = await AudioGrpc.audioPlayList(
      account: account,
      id: anchor.id,
      oid: initial ? anchor.oid : null,
      subId: initial ? anchor.subIds : null,
      itemType: initial ? anchor.itemType : null,
      from: initial ? _source(anchor.source) : null,
      extraId: anchor.extraId,
      order: switch (order) {
        .unordered => ListOrder.NO_ORDER,
        .normal => ListOrder.ORDER_NORMAL,
        .reverse => ListOrder.ORDER_REVERSE,
        .random => ListOrder.ORDER_RANDOM,
      },
      next: cursor,
    );
    return switch (result) {
      Success(:final response) => Success((
        items: response.list.map(_track).toList(growable: false),
        previous: _cursor(response.reachStart, response.paginationReply.prev),
        next: _cursor(response.reachEnd, response.paginationReply.next),
      )),
      Error() => result,
      Loading() => const Error('播放列表尚未加载完成，请重试'),
    };
  }

  static String? _cursor(bool ended, String cursor) =>
      ended || cursor.isEmpty ? null : cursor;

  static PlaylistSource _source(AudioPlaylistSource source) => switch (source) {
    .fallback => PlaylistSource.DEFAULT,
    .memberSpace => PlaylistSource.MEM_SPACE,
    .audioCard => PlaylistSource.AUDIO_CARD,
    .favorite => PlaylistSource.USER_FAVOURITE,
    .archive => PlaylistSource.UP_ARCHIVE,
    .mediaList => PlaylistSource.MEDIA_LIST,
  };

  static AudioTrack _track(DetailItem item) {
    final archive = item.arc;
    final artist = item.owner;
    final stats = item.stat;
    final associated = item.associatedItem;
    return AudioTrack(
      AudioTrackInfo(
        target: (
          oid: item.item.oid,
          type: item.item.itemType,
          parts: List.unmodifiable(item.item.subId),
        ),
        title: archive.title,
        cover: archive.cover,
        duration: archive.duration.toInt(),
        publishedAt: archive.publish.toInt(),
        displayedId: archive.displayedOid,
        description: archive.hasDesc() ? archive.desc : null,
        copyright: archive.copyright,
        artistId: artist.mid,
        artistName: artist.hasName() ? artist.name : null,
        artistAvatar: artist.hasAvatar() ? artist.avatar : null,
        parts: List.unmodifiable(
          item.parts.map(
            (part) => (oid: part.oid, subId: part.subId, title: part.title),
          ),
        ),
        musicVideo: associated.hasOid() && associated.subId.isNotEmpty
            ? (aid: associated.oid.toInt(), cid: associated.subId.first.toInt())
            : null,
      ),
      stats: AudioTrackStats(
        likes: stats.like,
        coins: stats.coin,
        favorites: stats.favourite,
        replies: stats.reply,
        shares: stats.share,
        views: stats.view,
        liked: stats.hasLike_7,
        viewerCoins: stats.hasCoin_8 ? 2 : 0,
        favored: stats.hasFav,
      ),
    );
  }
}
