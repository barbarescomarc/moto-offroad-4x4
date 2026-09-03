// test/services/guidance_voice_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/guidance_voice_service.dart';

class _FakeTtsEngine implements TtsEngine {
  final List<String> spoken = [];
  bool stopped = false;
  String? language;

  @override
  Future<void> setLanguage(String lang) async => language = lang;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stopped = true;
}

void main() {
  test('configure le français au démarrage', () {
    final engine = _FakeTtsEngine();
    GuidanceVoiceService(engine: engine);
    expect(engine.language, 'fr-FR');
  });

  test('announce parle quand le service n\'est pas muet', () async {
    final engine = _FakeTtsEngine();
    final voice = GuidanceVoiceService(engine: engine);
    await voice.announce('Tournez à gauche');
    expect(engine.spoken, ['Tournez à gauche']);
  });

  test('announce ne parle pas quand le service est muet', () async {
    final engine = _FakeTtsEngine();
    final voice = GuidanceVoiceService(engine: engine);
    voice.setMuted(true);
    await voice.announce('Tournez à gauche');
    expect(engine.spoken, isEmpty);
  });

  test('couper le son arrête une annonce en cours', () {
    final engine = _FakeTtsEngine();
    final voice = GuidanceVoiceService(engine: engine);
    voice.setMuted(true);
    expect(engine.stopped, isTrue);
  });

  test('isMuted reflète le dernier setMuted', () {
    final engine = _FakeTtsEngine();
    final voice = GuidanceVoiceService(engine: engine);
    expect(voice.isMuted, isFalse);
    voice.setMuted(true);
    expect(voice.isMuted, isTrue);
  });
}
