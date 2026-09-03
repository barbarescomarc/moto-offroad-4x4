import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/providers/favorites_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('aucun favori par défaut', () async {
    SharedPreferences.setMockInitialValues({});
    final p = FavoritesProvider();
    await p.load();
    expect(p.places, isEmpty);
  });

  test('ajouter un favori le rend disponible et le persiste', () async {
    SharedPreferences.setMockInitialValues({});
    final p = FavoritesProvider();
    await p.load();
    await p.add('Garage', const LatLng(44.0, 6.0));

    expect(p.places, hasLength(1));
    expect(p.places.single.name, 'Garage');

    final reloaded = FavoritesProvider();
    await reloaded.load();
    expect(reloaded.places, hasLength(1));
    expect(reloaded.places.single.name, 'Garage');
  });

  test('supprimer un favori le retire de la liste et de la persistance', () async {
    SharedPreferences.setMockInitialValues({});
    final p = FavoritesProvider();
    await p.load();
    await p.add('Garage', const LatLng(44.0, 6.0));
    final id = p.places.single.id;

    await p.remove(id);
    expect(p.places, isEmpty);

    final reloaded = FavoritesProvider();
    await reloaded.load();
    expect(reloaded.places, isEmpty);
  });

  test('une sauvegarde corrompue ne fait pas planter le chargement', () async {
    SharedPreferences.setMockInitialValues({'favorite_places': 'pas du json valide'});
    final p = FavoritesProvider();
    await p.load();
    expect(p.places, isEmpty);
  });
}
