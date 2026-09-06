import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/services/speed_taunt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('vitesse excessive déclenche le message une seule fois par jour', () async {
    var now = DateTime(2026, 1, 1, 10, 0);
    final service = SpeedTauntService(clock: () => now);

    expect(await service.onSpeed(180), SpeedTaunt.tooFast);
    // Toujours au-dessus du seuil, même jour : plus de message.
    expect(await service.onSpeed(180), null);

    now = DateTime(2026, 1, 2, 10, 0);
    expect(await service.onSpeed(180), SpeedTaunt.tooFast);
  });

  test('vitesse sous le seuil sans être soutenue ne déclenche rien', () async {
    var now = DateTime(2026, 1, 1, 10, 0);
    final service = SpeedTauntService(clock: () => now);

    expect(await service.onSpeed(20), null);
    now = now.add(const Duration(minutes: 2));
    expect(await service.onSpeed(20), null);
  });

  test('lenteur soutenue plus de 3 minutes déclenche le message', () async {
    var now = DateTime(2026, 1, 1, 10, 0);
    final service = SpeedTauntService(clock: () => now);

    expect(await service.onSpeed(20), null);
    now = now.add(const Duration(minutes: 3, seconds: 1));
    expect(await service.onSpeed(20), SpeedTaunt.tooSlow);
    // Toujours lent, même jour : plus de message.
    expect(await service.onSpeed(20), null);
  });

  test('repasser au-dessus du seuil lent avant 3 minutes réinitialise le compteur', () async {
    var now = DateTime(2026, 1, 1, 10, 0);
    final service = SpeedTauntService(clock: () => now);

    expect(await service.onSpeed(20), null);
    now = now.add(const Duration(minutes: 2));
    expect(await service.onSpeed(50), null); // au-dessus du seuil : reset
    now = now.add(const Duration(minutes: 2));
    expect(await service.onSpeed(20), null); // seulement 2 min de lenteur depuis le reset
  });

  test('les deux messages sont indépendants le même jour', () async {
    var now = DateTime(2026, 1, 1, 10, 0);
    final service = SpeedTauntService(clock: () => now);

    expect(await service.onSpeed(180), SpeedTaunt.tooFast);
    expect(await service.onSpeed(20), null); // amorce le compteur de lenteur
    now = now.add(const Duration(minutes: 3, seconds: 1));
    expect(await service.onSpeed(20), SpeedTaunt.tooSlow);
  });
}
