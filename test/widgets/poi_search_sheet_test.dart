// test/widgets/poi_search_sheet_test.dart
//
// La feuille de recherche ne propose que ce que le véhicule sait exploiter :
// une aire de camping-car offerte à une moto est un filtre que personne ne
// cochera, et l'aire manquante au camping-car est la recherche la plus utile
// du lot.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/models/vehicle_kind.dart';
import 'package:moto_offroad/providers/guidance_provider.dart';
import 'package:moto_offroad/providers/poi_search_provider.dart';
import 'package:moto_offroad/providers/settings_provider.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/widgets/poi_search_sheet.dart';

Future<SettingsProvider> _reglagesAvec(VehicleKind vehicule) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsProvider();
  await settings.load();
  await settings.setVehicleKind(vehicule);
  return settings;
}

Widget _monter(SettingsProvider settings) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => PoiSearchProvider()),
        ChangeNotifierProvider(create: (_) => GuidanceProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PoiSearchSheet(locationService: LocationService()),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('le camping-car peut chercher une aire', (tester) async {
    final settings = await _reglagesAvec(VehicleKind.van);

    await tester.pumpWidget(_monter(settings));

    expect(find.textContaining('Aire camping-car'), findsOneWidget);
  });

  testWidgets('la moto ne se voit pas proposer d aire', (tester) async {
    final settings = await _reglagesAvec(VehicleKind.moto);

    await tester.pumpWidget(_monter(settings));

    expect(find.textContaining('Aire camping-car'), findsNothing);
    expect(find.textContaining('Point de vue'), findsOneWidget);
  });

  testWidgets('le camping-car ouvre la feuille sur l aire déjà cochée',
      (tester) async {
    final settings = await _reglagesAvec(VehicleKind.van);

    await tester.pumpWidget(_monter(settings));

    final puce = tester.widget<FilterChip>(
      find.ancestor(
        of: find.textContaining('Aire camping-car'),
        matching: find.byType(FilterChip),
      ),
    );
    expect(puce.selected, isTrue);
  });

  testWidgets('la moto ouvre la feuille sur le point de vue', (tester) async {
    final settings = await _reglagesAvec(VehicleKind.moto);

    await tester.pumpWidget(_monter(settings));

    final puce = tester.widget<FilterChip>(
      find.ancestor(
        of: find.textContaining('Point de vue'),
        matching: find.byType(FilterChip),
      ),
    );
    expect(puce.selected, isTrue);
  });
}
