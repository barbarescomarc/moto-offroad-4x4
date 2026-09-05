// test/screens/favorites_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/providers/favorites_provider.dart';
import 'package:moto_offroad/screens/favorites/favorites_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('affiche un message quand aucun favori', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final favorites = FavoritesProvider();
    await favorites.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: favorites,
        child: const MaterialApp(home: FavoritesScreen()),
      ),
    );

    expect(find.textContaining('Aucun favori'), findsOneWidget);
  });

  testWidgets('affiche la liste et supprime un favori', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final favorites = FavoritesProvider();
    await favorites.load();
    await favorites.add('Garage', const LatLng(44.0, 6.0));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: favorites,
        child: const MaterialApp(home: FavoritesScreen()),
      ),
    );

    expect(find.text('Garage'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Garage'), findsNothing);
  });
}
