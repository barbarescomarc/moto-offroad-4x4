// test/providers/poi_search_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/poi.dart';
import 'package:moto_offroad/providers/poi_search_provider.dart';
import 'package:moto_offroad/services/data_tourisme_service.dart';

class _FakeDataTourismeService extends DataTourismeService {
  List<PoiModel> nextAroundResult = const [];
  List<PoiModel> nextRouteResult = const [];
  LatLng? lastAroundPoint;
  List<LatLng>? lastRoutePolyline;

  @override
  Future<List<PoiModel>> searchAround(LatLng point, {required double radiusKm, required Set<PoiCategory> categories}) async {
    lastAroundPoint = point;
    return nextAroundResult;
  }

  @override
  Future<List<PoiModel>> searchAlongRoute(List<LatLng> polyline, {required double radiusKm, required Set<PoiCategory> categories}) async {
    lastRoutePolyline = polyline;
    return nextRouteResult;
  }
}

PoiModel _poi(String id) => PoiModel(
  id: id, name: 'Test', category: PoiCategory.viewpoint, position: const LatLng(45.0, 5.0),
);

void main() {
  group('PoiSearchProvider', () {
    test('mode aroundMe/atDestination interroge searchAround avec le point donné', () async {
      final service = _FakeDataTourismeService()..nextAroundResult = [_poi('a')];
      final provider = PoiSearchProvider(service: service);

      await provider.search(
        mode: PoiSearchMode.aroundMe,
        categories: {PoiCategory.viewpoint},
        aroundPoint: const LatLng(45.1, 5.1),
      );

      expect(service.lastAroundPoint, const LatLng(45.1, 5.1));
      expect(provider.results, hasLength(1));
      expect(provider.isSearching, isFalse);
    });

    test('mode alongRoute interroge searchAlongRoute avec le tracé donné', () async {
      final polyline = [const LatLng(45.0, 5.0), const LatLng(45.1, 5.1)];
      final service = _FakeDataTourismeService()..nextRouteResult = [_poi('b'), _poi('c')];
      final provider = PoiSearchProvider(service: service);

      await provider.search(
        mode: PoiSearchMode.alongRoute,
        categories: {PoiCategory.heritage},
        routePolyline: polyline,
      );

      expect(service.lastRoutePolyline, polyline);
      expect(provider.results, hasLength(2));
    });

    test('sans point ni tracé, la recherche renvoie une liste vide sans planter', () async {
      final provider = PoiSearchProvider(service: _FakeDataTourismeService());

      await provider.search(mode: PoiSearchMode.atDestination, categories: {PoiCategory.viewpoint});

      expect(provider.results, isEmpty);
    });

    test('clear() vide les résultats', () async {
      final service = _FakeDataTourismeService()..nextAroundResult = [_poi('a')];
      final provider = PoiSearchProvider(service: service);
      await provider.search(
        mode: PoiSearchMode.aroundMe,
        categories: {PoiCategory.viewpoint},
        aroundPoint: const LatLng(45.0, 5.0),
      );
      expect(provider.results, isNotEmpty);

      provider.clear();

      expect(provider.results, isEmpty);
    });
  });
}
