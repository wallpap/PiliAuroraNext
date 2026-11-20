import 'package:media_kit/media_kit.dart' show Player;
import 'package:pili_aurora_next/features/sponsor_block/application/playback_preferences.dart';
import 'package:pili_aurora_next/pages/sponsor_block/block_mixin.dart';

class AudioSegmentAdapter with BlockConfigMixin, BlockMixin {
  AudioSegmentAdapter({
    required this._isUgc,
    required this._player,
    required this._seek,
  });

  final bool Function() _isUgc;
  final Player? Function() _player;
  final Future<void> Function(Duration) _seek;

  @override
  bool get isUgc => _isUgc();

  @override
  Player? get player => _player();

  @override
  BlockConfigMixin get blockConfig => this;

  @override
  Future<void> applyBlockMute(bool muted) async {
    player?.setProperty('mute', muted ? 'yes' : 'no');
  }

  @override
  int get currPosInMilliseconds => player?.state.position.inMilliseconds ?? 0;

  @override
  int? get timeLength => player?.state.duration.inMilliseconds ?? 0;

  @override
  Future<void> seekTo(Duration duration, {required bool isSeek}) =>
      _seek(duration);

  @override
  bool get autoPlay => true;

  @override
  bool get preInitPlayer => true;
}
