// test/providers/map_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/providers/map_provider.dart';

void main() {
  group('navigationTileUrl', () {
    test('rend le fond clair en journée', () {
      final mapProv = MapProvider();
      final url = mapProv.navigationTileUrl(now: () => DateTime(2026, 1, 1, 12));
      expect(url, contains('light_all'));
    });

    test('rend le fond sombre la nuit', () {
      final mapProv = MapProvider();
      final url = mapProv.navigationTileUrl(now: () => DateTime(2026, 1, 1, 23));
      expect(url, contains('dark_all'));
    });
  });
}
