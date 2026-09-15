// test/providers/garage_test.dart
//
// Le garage : ce que le pilote possède, par opposition à ce qu'il conduit
// aujourd'hui. Un seul véhicule dans le garage, et il n'y a plus rien à
// choisir — c'est cette règle qui fait disparaître le sélecteur de l'en-tête.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/models/vehicle_kind.dart';
import 'package:moto_offroad/providers/settings_provider.dart';

Future<SettingsProvider> _reglages() async {
  final s = SettingsProvider();
  await s.load();
  return s;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('au départ, le garage ne contient que le véhicule sélectionné', () async {
    final s = await _reglages();
    expect(s.garage, {s.vehicleKind});
    expect(s.plusieursVehicules, isFalse);
  });

  test('ajouter un véhicule au garage ne change pas celui qu on conduit', () async {
    final s = await _reglages();
    final conduit = s.vehicleKind;
    await s.ajouterAuGarage(VehicleKind.van);
    expect(s.garage, containsAll([conduit, VehicleKind.van]));
    expect(s.vehicleKind, conduit);
    expect(s.plusieursVehicules, isTrue);
  });

  test('on ne peut pas selectionner un vehicule absent du garage', () async {
    final s = await _reglages();
    await s.setVehicleKind(VehicleKind.van);
    // Le van n'est pas au garage : le sélectionner l'y fait entrer, sans
    // quoi l'app afficherait un véhicule que le pilote ne possède pas.
    expect(s.garage, contains(VehicleKind.van));
    expect(s.vehicleKind, VehicleKind.van);
  });

  test('retirer le vehicule conduit bascule sur un autre du garage', () async {
    final s = await _reglages();
    await s.ajouterAuGarage(VehicleKind.van);
    await s.setVehicleKind(VehicleKind.van);

    await s.retirerDuGarage(VehicleKind.van);

    expect(s.garage, isNot(contains(VehicleKind.van)));
    expect(s.vehicleKind, isNot(VehicleKind.van),
        reason: 'on ne conduit pas un véhicule qu on vient de vendre');
    expect(s.garage, contains(s.vehicleKind));
  });

  test('le dernier vehicule ne peut pas quitter le garage', () async {
    final s = await _reglages();
    await s.retirerDuGarage(s.vehicleKind);
    expect(s.garage, hasLength(1),
        reason: 'un garage vide laisserait l app sans gabarit ni profil');
  });

  test('le garage survit au redemarrage', () async {
    final s = await _reglages();
    await s.ajouterAuGarage(VehicleKind.van);
    await s.ajouterAuGarage(VehicleKind.quatreQuatre);

    final relu = await _reglages();
    expect(relu.garage, hasLength(3));
  });

  test('une installation d avant lit encore son vehicule', () async {
    // L'ancien enregistrement portait un index : 2 valait le van. Depuis
    // que la moto de route s'est insérée dans l'énumération, cet index
    // désigne le 4x4 — le relire tel quel changerait le véhicule du pilote.
    SharedPreferences.setMockInitialValues({'vehicle_kind': 2});
    final s = await _reglages();
    expect(s.vehicleKind, VehicleKind.van);
  });

  test('la moto de route ne coupe pas par la piste', () async {
    final s = await _reglages();
    await s.setVehicleKind(VehicleKind.motoRoute);
    expect(s.autoriseHorsRoute, isFalse,
        reason: 'c est ce qui la distingue de la moto tout-terrain');

    await s.setVehicleKind(VehicleKind.moto);
    expect(s.autoriseHorsRoute, isTrue);
  });

  test('le vehicule suivant tourne en rond dans le garage', () async {
    final s = await _reglages();
    await s.ajouterAuGarage(VehicleKind.van);
    final premier = s.vehicleKind;

    await s.vehiculeSuivant();
    expect(s.vehicleKind, isNot(premier));
    await s.vehiculeSuivant();
    expect(s.vehicleKind, premier, reason: 'deux véhicules : on revient au départ');
  });
}
