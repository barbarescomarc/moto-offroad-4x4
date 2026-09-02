import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les valeurs par défaut sont celles du spec', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    expect(s.autoPauseEnabled, isTrue);
    expect(s.pauseSpeedKmh, 2);
    expect(s.askNameOnStop, isFalse);
    expect(s.suggestAutoStart, isFalse);
    expect(s.useMiles, isFalse);
    expect(s.keepScreenOnMap, isTrue);
  });

  test('les réglages survivent à un rechargement', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    await s.setAutoPauseEnabled(false);
    await s.setPauseSpeedKmh(5);
    await s.setAskNameOnStop(true);
    await s.setKeepScreenOnMap(false);

    final reloaded = SettingsProvider();
    await reloaded.load();
    expect(reloaded.autoPauseEnabled, isFalse);
    expect(reloaded.pauseSpeedKmh, 5);
    expect(reloaded.askNameOnStop, isTrue);
    expect(reloaded.keepScreenOnMap, isFalse);
  });

  test('un seuil de pause hors des valeurs prévues retombe sur 2', () async {
    SharedPreferences.setMockInitialValues({'rec_pause_speed': 17});
    final s = SettingsProvider();
    await s.load();
    expect(s.pauseSpeedKmh, 2);
  });
}
