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
    expect(s.autoHideNavBar, isTrue);
  });

  test('les réglages survivent à un rechargement', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    await s.setAutoPauseEnabled(false);
    await s.setPauseSpeedKmh(5);
    await s.setAskNameOnStop(true);
    await s.setKeepScreenOnMap(false);
    await s.setAutoHideNavBar(false);

    final reloaded = SettingsProvider();
    await reloaded.load();
    expect(reloaded.autoPauseEnabled, isFalse);
    expect(reloaded.pauseSpeedKmh, 5);
    expect(reloaded.askNameOnStop, isTrue);
    expect(reloaded.keepScreenOnMap, isFalse);
    expect(reloaded.autoHideNavBar, isFalse);
  });

  test('un seuil de pause hors des valeurs prévues retombe sur 2', () async {
    SharedPreferences.setMockInitialValues({'rec_pause_speed': 17});
    final s = SettingsProvider();
    await s.load();
    expect(s.pauseSpeedKmh, 2);
  });

  test('le seuil de coupure de signal se règle et survit au rechargement',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    expect(s.signalGapSeconds, 90);

    await s.setSignalGapSeconds(180);
    final relu = SettingsProvider();
    await relu.load();
    expect(relu.signalGapSeconds, 180);
  });

  test('un seuil de coupure hors des valeurs prévues retombe sur 90', () async {
    SharedPreferences.setMockInitialValues({'rec_signal_gap': 7});
    final s = SettingsProvider();
    await s.load();
    expect(s.signalGapSeconds, 90);
  });

  test('les réglages d auto-réponse ont les valeurs par défaut du spec', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    expect(s.autoReplyEnabled, isTrue);
    expect(s.autoReplyAttachPosition, isTrue);
    expect(s.autoReplyAllCallers, isFalse);
    expect(s.autoReplyMessage, 'Je roule, je ne peux pas répondre');
  });

  test('les réglages d auto-réponse survivent à un rechargement', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    await s.setAutoReplyEnabled(false);
    await s.setAutoReplyAttachPosition(false);
    await s.setAutoReplyAllCallers(true);
    await s.setAutoReplyMessage('Je pilote, rappelle plus tard');

    final reloaded = SettingsProvider();
    await reloaded.load();
    expect(reloaded.autoReplyEnabled, isFalse);
    expect(reloaded.autoReplyAttachPosition, isFalse);
    expect(reloaded.autoReplyAllCallers, isTrue);
    expect(reloaded.autoReplyMessage, 'Je pilote, rappelle plus tard');
  });

  test('un message d auto-réponse vide retombe sur la valeur par défaut', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    await s.setAutoReplyMessage('   ');
    expect(s.autoReplyMessage, 'Je roule, je ne peux pas répondre');
  });

  test('pilot email and newsletter opt-in persist', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    expect(s.pilotEmail, '');
    expect(s.pilotNewsletterOptIn, false);

    await s.setPilotEmail('marc@example.test');
    await s.setPilotNewsletterOptIn(true);

    final reloaded = SettingsProvider();
    await reloaded.load();
    expect(reloaded.pilotEmail, 'marc@example.test');
    expect(reloaded.pilotNewsletterOptIn, true);
  });

  test('fall detection settings default and persist', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    expect(s.fallDetectionEnabled, true);
    expect(s.fallCountdownSeconds, 30);
    expect(s.alertChannelPhone, true);
    expect(s.alertChannelServer, true);

    await s.setFallDetectionEnabled(false);
    await s.setFallCountdownSeconds(60);
    await s.setAlertChannelPhone(false);
    await s.setAlertChannelServer(false);

    final reloaded = SettingsProvider();
    await reloaded.load();
    expect(reloaded.fallDetectionEnabled, false);
    expect(reloaded.fallCountdownSeconds, 60);
    expect(reloaded.alertChannelPhone, false);
    expect(reloaded.alertChannelServer, false);
  });

  test('fall countdown seconds is clamped to 15-120', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    await s.setFallCountdownSeconds(5);
    expect(s.fallCountdownSeconds, 15);
    await s.setFallCountdownSeconds(999);
    expect(s.fallCountdownSeconds, 120);
  });
}
