import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/models/vehicle_kind.dart';
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

  test('les réglages de guidage par défaut sont désactivés', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    expect(s.guidanceAvoidHighways, isFalse);
    expect(s.guidanceAvoidTolls, isFalse);
    expect(s.guidanceAvoidFerries, isFalse);
    expect(s.guidanceVoiceMuted, isFalse);
    expect(s.mapHeadingUp, isFalse);
  });

  test('les réglages de guidage survivent à un rechargement', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    await s.setGuidanceAvoidHighways(true);
    await s.setGuidanceAvoidTolls(true);
    await s.setGuidanceAvoidFerries(true);
    await s.setGuidanceVoiceMuted(true);
    await s.toggleMapHeadingUp();

    final reloaded = SettingsProvider();
    await reloaded.load();
    expect(reloaded.guidanceAvoidHighways, isTrue);
    expect(reloaded.guidanceAvoidTolls, isTrue);
    expect(reloaded.guidanceAvoidFerries, isTrue);
    expect(reloaded.guidanceVoiceMuted, isTrue);
    expect(reloaded.mapHeadingUp, isTrue);
  });

  test('toggleMapHeadingUp bascule dans les deux sens', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    expect(s.mapHeadingUp, isFalse);
    await s.toggleMapHeadingUp();
    expect(s.mapHeadingUp, isTrue);
    await s.toggleMapHeadingUp();
    expect(s.mapHeadingUp, isFalse);
  });

  // Le bandeau de diagnostic des tuiles est un outil de depannage, pas un
  // element de conduite : il ne doit jamais s'inviter sur la carte sans
  // qu'on l'ait demande (choix du 2026-09-14).
  group('diagnostic des tuiles', () {
    test('eteint par defaut', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsProvider();
      await s.load();

      expect(s.tileDiagnostic, isFalse);
    });

    test('le choix survit au redemarrage', () async {
      SharedPreferences.setMockInitialValues({});
      final premiere = SettingsProvider();
      await premiere.load();
      await premiere.setTileDiagnostic(true);

      final seconde = SettingsProvider();
      await seconde.load();

      expect(seconde.tileDiagnostic, isTrue);
    });
  });

  // Les fourgons 4x4 existent : leur refuser la piste reviendrait a decider a
  // leur place. Mais un profile de 3,5 t n'a rien a y faire, donc le reglage
  // part ferme et ne s'ouvre que sur demande explicite.
  group('la piste pour le camping-car', () {
    test('fermee par defaut', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsProvider();
      await s.load();
      await s.setVehicleKind(VehicleKind.van);

      expect(s.vanToutTerrain, isFalse);
      expect(s.autoriseHorsRoute, isFalse);
    });

    test('ouverte, elle autorise le camping-car hors route', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsProvider();
      await s.load();
      await s.setVehicleKind(VehicleKind.van);
      await s.setVanToutTerrain(true);

      expect(s.autoriseHorsRoute, isTrue);
    });

    test('le choix survit au redemarrage', () async {
      SharedPreferences.setMockInitialValues({});
      final premiere = SettingsProvider();
      await premiere.load();
      await premiere.setVanToutTerrain(true);

      final seconde = SettingsProvider();
      await seconde.load();

      expect(seconde.vanToutTerrain, isTrue);
    });

    test('les autres vehicules vont hors route sans rien demander', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsProvider();
      await s.load();
      await s.setVehicleKind(VehicleKind.moto);

      expect(s.vanToutTerrain, isFalse);
      expect(s.autoriseHorsRoute, isTrue);
    });

    test('le gabarit reste transmis meme piste ouverte', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsProvider();
      await s.load();
      await s.setVehicleKind(VehicleKind.van);
      await s.setVanToutTerrain(true);

      expect(s.gabarit, isNotNull);
    });
  });
}
