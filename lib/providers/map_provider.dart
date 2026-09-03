import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// ── Mode carte (couche de fond) ──────────────────────────────
enum MapLayer { satellite, osm, ign, contour }

extension MapLayerExt on MapLayer {
  String get label {
    switch (this) {
      case MapLayer.satellite: return 'Satellite';
      case MapLayer.osm:       return 'Chemins';
      case MapLayer.ign:       return 'IGN Topo';
      case MapLayer.contour:   return 'Topo (relief)';
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
        // Géoplateforme IGN — endpoint public, sans clé API (data.geopf.fr)
        return 'https://data.geopf.fr/wmts?'
               'SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
               '&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2'
               '&STYLE=normal&FORMAT=image/png'
               '&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}';
      case MapLayer.contour:
        // OpenTopoMap — gratuit, sans clé API, courbes de niveau mondiales
        return 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png';
    }
  }

  // Surcouche noms de rues/lieux — l'imagerie satellite Esri (World_Imagery)
  // est une photo pure, sans aucun texte. On superpose la couche de
  // référence Esri (fond transparent) pour retrouver les noms de rues et de
  // lieux, comme le mode « Hybride » de Google Maps. Non pertinent pour les
  // autres fonds, qui portent déjà leurs propres labels.
  String? get labelsOverlayUrl {
    if (this != MapLayer.satellite) return null;
    return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
           'Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';
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

  // Barre de navigation du bas — masquée pendant qu'on déplace la carte,
  // ramenée par un toucher près du bord. L'état vit ici plutôt que dans
  // MainShell, qui n'a pas de dépendance naturelle vers ce qui se passe sur
  // la carte ; MapScreen et MainShell lisent tous deux ce provider.
  bool _navBarVisible = true;
  bool get navBarVisible => _navBarVisible;

  void hideNavBar() {
    if (!_navBarVisible) return;
    _navBarVisible = false;
    notifyListeners();
  }

  void showNavBar() {
    if (_navBarVisible) return;
    _navBarVisible = true;
    notifyListeners();
  }

  // Radar pluie — RainViewer ne sert pas une URL fixe : chaque relevé porte
  // un chemin distinct (ex. /v2/radar/b215c3c68ec1), à lire dans son API de
  // métadonnées et à rafraîchir régulièrement, un relevé n'étant conservé
  // que quelques dizaines de minutes.
  bool _radarEnabled = false;
  bool get radarEnabled => _radarEnabled;

  String? _radarTilePath;
  String? get radarTileUrlTemplate => _radarTilePath == null
      ? null
      : 'https://tilecache.rainviewer.com$_radarTilePath/256/{z}/{x}/{y}/4/1_1.png';

  Timer? _radarRefreshTimer;

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
    if (_radarEnabled) {
      _refreshRadarPath();
      _radarRefreshTimer?.cancel();
      _radarRefreshTimer = Timer.periodic(
        const Duration(minutes: 10), (_) => _refreshRadarPath());
    } else {
      _radarRefreshTimer?.cancel();
      _radarRefreshTimer = null;
      _radarTilePath = null;
    }
    notifyListeners();
  }

  // Interroge la liste des relevés disponibles et retient le plus récent.
  Future<void> _refreshRadarPath() async {
    try {
      final resp = await http.get(
        Uri.parse('https://api.rainviewer.com/public/weather-maps.json'),
      );
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final past = (data['radar'] as Map<String, dynamic>?)?['past'] as List<dynamic>?;
      if (past == null || past.isEmpty) return;
      final path = (past.last as Map<String, dynamic>)['path'] as String?;
      if (path == null || !_radarEnabled) return;
      _radarTilePath = path;
      notifyListeners();
    } catch (_) {
      // Pas de réseau ou service indisponible : le radar reste simplement
      // éteint jusqu'au prochain essai, sans faire planter la carte.
    }
  }

  @override
  void dispose() {
    _radarRefreshTimer?.cancel();
    super.dispose();
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
