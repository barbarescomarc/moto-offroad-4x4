import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

// ── Mode carte (couche de fond) ──────────────────────────────
enum MapLayer { satellite, osm, ign, contour }

extension MapLayerExt on MapLayer {
  String get label {
    switch (this) {
      case MapLayer.satellite: return 'Satellite';
      case MapLayer.osm:       return 'Chemins';
      case MapLayer.ign:       return 'IGN Topo';
      case MapLayer.contour:   return 'État-Major';
    }
  }

  // URLs des tuiles
  String get tileUrl {
    switch (this) {
      case MapLayer.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
               'World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case MapLayer.osm:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapLayer.ign:
        // Géoportail IGN — nécessite une clé API
        return 'https://wxs.ign.fr/{apiKey}/geoportail/wmts?'
               'SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
               '&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2'
               '&STYLE=normal&FORMAT=image/png'
               '&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}';
      case MapLayer.contour:
        // OpenTopoMap — gratuit, sans clé API, courbes de niveau mondiales
        return 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png';
    }
  }
}

// ── Mode de navigation ───────────────────────────────────────
enum NavMode { offroad, route }

// ── Provider — État de la carte ──────────────────────────────
class MapProvider extends ChangeNotifier {
  // Couche de fond
  MapLayer _activeLayer = MapLayer.osm;
  MapLayer get activeLayer => _activeLayer;

  // Mode navigation
  NavMode _navMode = NavMode.offroad;
  NavMode get navMode => _navMode;
  bool get isOffroad => _navMode == NavMode.offroad;

  // Plein écran
  bool _isFullscreen = false;
  bool get isFullscreen => _isFullscreen;

  // Radar pluie
  bool _radarEnabled = false;
  bool get radarEnabled => _radarEnabled;

  // Overlay impraticabilité
  bool _practicabilityEnabled = true;
  bool get practicabilityEnabled => _practicabilityEnabled;

  // Suivi auto de la position (carte centrée sur le rider)
  bool _followPosition = true;
  bool get followPosition => _followPosition;

  // Zoom actuel
  double _zoom = 14.0;
  double get zoom => _zoom;

  // Centre actuel
  LatLng _center = const LatLng(44.5, 6.5); // Alpes du Sud par défaut
  LatLng get center => _center;

  // POI activés par catégorie
  final Map<String, bool> _poiFilters = {
    'gasStation': true,
    'restaurant': false,
    'hotel':      false,
    'camping':    false,
    'motoShop':   true,
    'bivouac':    false,
  };
  Map<String, bool> get poiFilters => Map.unmodifiable(_poiFilters);

  // ── Actions ─────────────────────────────────────────────

  void setLayer(MapLayer layer) {
    _activeLayer = layer;
    notifyListeners();
  }

  void setNavMode(NavMode mode) {
    _navMode = mode;
    notifyListeners();
  }

  void toggleNavMode() {
    _navMode = _navMode == NavMode.offroad ? NavMode.route : NavMode.offroad;
    notifyListeners();
  }

  void toggleFullscreen() {
    _isFullscreen = !_isFullscreen;
    notifyListeners();
  }

  void exitFullscreen() {
    _isFullscreen = false;
    notifyListeners();
  }

  void toggleRadar() {
    _radarEnabled = !_radarEnabled;
    notifyListeners();
  }

  void togglePracticability() {
    _practicabilityEnabled = !_practicabilityEnabled;
    notifyListeners();
  }

  void toggleFollowPosition() {
    _followPosition = !_followPosition;
    notifyListeners();
  }

  void setCenter(LatLng center, {double? zoom}) {
    _center = center;
    if (zoom != null) _zoom = zoom;
    notifyListeners();
  }

  void setZoom(double zoom) {
    _zoom = zoom;
    notifyListeners();
  }

  void setPoiFilter(String key, bool enabled) {
    _poiFilters[key] = enabled;
    notifyListeners();
  }
}
