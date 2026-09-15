// test/widgets/selecteur_vehicule_test.dart
//
// Le sélecteur de véhicule de l'en-tête. Sa règle tient en une phrase : il
// n'existe que s'il y a un choix à faire. Un pilote qui n'a qu'une moto ne
// doit pas voir un bouton qui lui propose de choisir sa moto.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/models/vehicle_kind.dart';
import 'package:moto_offroad/providers/settings_provider.dart';
import 'package:moto_offroad/widgets/radial_action_menu.dart';
import 'package:moto_offroad/widgets/selecteur_vehicule.dart';

Future<SettingsProvider> _reglages(List<VehicleKind> garage) async {
  SharedPreferences.setMockInitialValues({});
  final s = SettingsProvider();
  await s.load();
  for (final v in garage) {
    await s.ajouterAuGarage(v);
  }
  return s;
}

Future<void> _monter(WidgetTester tester, SettingsProvider settings) =>
    tester.pumpWidget(ChangeNotifierProvider.value(
      value: settings,
      child: const MaterialApp(home: Scaffold(body: Center(child: SelecteurVehicule()))),
    ));

void main() {
  testWidgets('un seul vehicule : aucun selecteur', (tester) async {
    await _monter(tester, await _reglages([]));
    expect(find.byType(RadialActionMenu), findsNothing);
  });

  testWidgets('deux vehicules : un cadran avec l autre en segment', (tester) async {
    final settings = await _reglages([VehicleKind.van]);
    await _monter(tester, settings);

    expect(find.byType(RadialActionMenu), findsOneWidget);
    final menu = tester.widget<RadialActionMenu>(find.byType(RadialActionMenu));
    expect(menu.centerIcon, settings.vehicleKind.icon);
    expect(menu.segments, hasLength(1),
        reason: 'le véhicule conduit est le centre, pas un segment');
    expect(menu.segments.first.icon, VehicleKind.van.icon);
  });

  testWidgets('l appui court passe au vehicule suivant', (tester) async {
    final settings = await _reglages([VehicleKind.van]);
    final depart = settings.vehicleKind;
    await _monter(tester, settings);

    await tester.tap(find.byType(RadialActionMenu));
    await tester.pumpAndSettle();

    expect(settings.vehicleKind, isNot(depart));
  });
}
