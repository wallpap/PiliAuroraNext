import 'package:fixnum/fixnum.dart';

enum AudioPlaylistSource {
  fallback,
  memberSpace,
  audioCard,
  favorite,
  archive,
  mediaList,
}

enum AudioPlaylistOrder { unordered, normal, reverse, random }

typedef AudioTarget = ({Int64 oid, int type, List<Int64> parts});

typedef AudioPart = ({Int64 oid, Int64 subId, String title});

class AudioTrackInfo {
  const AudioTrackInfo({
    required this.target,
    this.title = '',
    this.cover = '',
    this.duration = 0,
    this.publishedAt = 0,
    this.displayedId = '',
    this.description,
    this.copyright = 0,
    this.artistId = Int64.ZERO,
    this.artistName,
    this.artistAvatar,
    this.parts = const [],
    this.musicVideo,
  });

  final AudioTarget target;
  final String title;
  final String cover;
  final int duration;
  final int publishedAt;
  final String displayedId;
  final String? description;
  final int copyright;
  final Int64 artistId;
  final String? artistName;
  final String? artistAvatar;
  final List<AudioPart> parts;
  final ({int aid, int cid})? musicVideo;
}

class AudioTrackStats {
  const AudioTrackStats({
    this.likes = 0,
    this.coins = 0,
    this.favorites = 0,
    this.replies = 0,
    this.shares = 0,
    this.views = 0,
    this.liked = false,
    this.viewerCoins = 0,
    this.favored = false,
  });

  final int likes;
  final int coins;
  final int favorites;
  final int replies;
  final int shares;
  final int views;
  final bool liked;
  final int viewerCoins;
  final bool favored;

  AudioTrackStats confirm({bool? like, int addedCoins = 0, bool? favorite}) =>
      AudioTrackStats(
        likes: like == null || like == liked ? likes : likes + (like ? 1 : -1),
        coins: coins + addedCoins,
        favorites: favorite == null || favorite == favored
            ? favorites
            : favorites + (favorite ? 1 : -1),
        replies: replies,
        shares: shares,
        views: views,
        liked: like ?? liked,
        viewerCoins: viewerCoins + addedCoins,
        favored: favorite ?? favored,
      );
}

class AudioTrack {
  const AudioTrack(this.info, {this.stats = const AudioTrackStats()});

  final AudioTrackInfo info;
  final AudioTrackStats stats;

  AudioTrack withStats(AudioTrackStats stats) => AudioTrack(info, stats: stats);
}
