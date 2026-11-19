import 'package:pili_aurora_next/services/audio_handler.dart';
import 'package:pili_aurora_next/services/audio_session.dart';

VideoPlayerServiceHandler? videoPlayerServiceHandler;
AudioSessionHandler? audioSessionHandler;
Future<void>? _audioSessionClosing;

Future<void> setupServiceLocator() async {
  final audio = await initAudioService();
  final session = AudioSessionHandler();
  await session.initSession();
  videoPlayerServiceHandler = audio;
  audioSessionHandler = session;
}

Future<void> closePlatformAudioSession() {
  final session = audioSessionHandler;
  if (session == null) return _audioSessionClosing ?? Future.value();
  audioSessionHandler = null;
  late final Future<void> closing;
  closing = session.dispose().whenComplete(() {
    if (identical(_audioSessionClosing, closing)) _audioSessionClosing = null;
  });
  return _audioSessionClosing = closing;
}
