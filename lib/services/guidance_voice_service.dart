import 'package:flutter_tts/flutter_tts.dart';

// Abstraction fine autour de flutter_tts, pour rester testable sans le
// canal de méthode de la plateforme.
abstract class TtsEngine {
  Future<void> setLanguage(String lang);
  Future<void> speak(String text);
  Future<void> stop();
}

class FlutterTtsEngine implements TtsEngine {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<void> setLanguage(String lang) => _tts.setLanguage(lang);

  @override
  Future<void> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();
}

class GuidanceVoiceService {
  GuidanceVoiceService({TtsEngine? engine}) : _engine = engine ?? FlutterTtsEngine() {
    _engine.setLanguage('fr-FR');
  }

  final TtsEngine _engine;
  bool _muted = false;
  bool get isMuted => _muted;

  void setMuted(bool muted) {
    _muted = muted;
    if (muted) _engine.stop();
  }

  Future<void> announce(String text) async {
    if (_muted) return;
    await _engine.speak(text);
  }
}
