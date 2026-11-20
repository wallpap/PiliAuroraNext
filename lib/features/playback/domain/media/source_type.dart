import 'package:pili_aurora_next/features/playback/domain/audio_track.dart';

enum SourceType {
  normal(
    mediaType: -1,
    playlistSource: AudioPlaylistSource.archive,
  ),
  archive(
    mediaType: 1,
    extraId: 1,
    playlistSource: AudioPlaylistSource.mediaList,
  ),
  watchLater(
    mediaType: 2,
    extraId: 2,
    playlistSource: AudioPlaylistSource.mediaList,
  ),
  fav(
    mediaType: 3,
    extraId: 2,
    playlistSource: AudioPlaylistSource.favorite,
  ),
  playlist(
    mediaType: 3,
    extraId: 4,
    playlistSource: AudioPlaylistSource.mediaList,
  ),
  file,
  ;

  final int? mediaType;
  final int? extraId;
  final AudioPlaylistSource? playlistSource;
  const SourceType({
    this.mediaType,
    this.extraId,
    this.playlistSource,
  });
}
