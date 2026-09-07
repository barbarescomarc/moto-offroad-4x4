// lib/providers/poi_search_provider.dart
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/poi.dart';
import '../services/data_tourisme_service.dart';

enum PoiSearchMode { aroundMe, atDestination, alongRoute }

// Recherche de POI DATAtourisme à la demande — pas de suivi continu de la
// position : l'utilisateur choisit une zone (autour de lui, à destination,
// le long de la route) et des catégories, puis lance la recherche.
class PoiSearchProvider extends ChangeNotifier {
  PoiSearchProvider({DataTourismeService? service}) : _service = service ?? DataTourismeService();

  final DataTourismeService _service;

  static const double radiusKm = 20;

  List<PoiModel> _results = const [];
  List<PoiModel> get results => _results;

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  Future<void> search({
    required PoiSearchMode mode,
    required Set<PoiCategory> categories,
    LatLng? aroundPoint,
    List<LatLng>? routePolyline,
  }) async {
    _isSearching = true;
    notifyListeners();

    List<PoiModel> found;
    if (mode == PoiSearchMode.alongRoute) {
      found = (routePolyline == null || routePolyline.isEmpty)
          ? const []
          : await _service.searchAlongRoute(routePolyline, radiusKm: radiusKm, categories: categories);
    } else {
      found = aroundPoint == null
          ? const []
          : await _service.searchAround(aroundPoint, radiusKm: radiusKm, categories: categories);
    }

    _results = found;
    _isSearching = false;
    notifyListeners();
  }

  void clear() {
    _results = const [];
    notifyListeners();
  }
}
