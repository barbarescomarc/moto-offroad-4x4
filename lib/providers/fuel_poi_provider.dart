import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/poi.dart';
import '../services/fuel_poi_service.dart';

/// Stations-service et réparateurs moto autour du pilote.
///
/// `unavailable` est distinct d'une liste vide : « aucune station dans ce
/// rayon » et « je n'ai pas pu joindre Overpass » n'appellent pas la même
/// conduite — la première fait élargir le rayon, la seconde fait réessayer.
class FuelPoiProvider extends ChangeNotifier {
  FuelPoiProvider({FuelPoiService? service}) : _service = service ?? FuelPoiService();

  final FuelPoiService _service;

  List<PoiModel> _results = const [];
  bool _loading = false;
  bool _unavailable = false;
  bool _visible = false;

  List<PoiModel> get results => _results;
  bool get loading => _loading;
  bool get unavailable => _unavailable;

  /// Les résultats sont-ils affichés sur la carte ?
  ///
  /// Distinct de « y a-t-il des résultats » : masquer n'est pas oublier. Le
  /// pilote qui éteint puis rallume doit les revoir instantanément, sans
  /// qu'on redemande à Overpass — service public, gratuit et irrégulier.
  bool get visible => _visible;

  Future<void> searchAround(LatLng center, {required int radiusKm}) async {
    _loading = true;
    notifyListeners();

    try {
      _results = await _service.fetchAround(center, radiusKm: radiusKm);
      // Une recherche qui aboutit efface l'échec précédent : sans cela, une
      // seule coupure laisserait le pilote devant un message de panne
      // définitif alors que le réseau est revenu.
      _unavailable = false;
      _visible = true;
    } on FuelPoiUnavailable {
      _results = const [];
      _unavailable = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Masque ou réaffiche les résultats déjà en mémoire, sans rien redemander.
  void toggleVisible() {
    _visible = !_visible;
    notifyListeners();
  }

  void clear() {
    _results = const [];
    _unavailable = false;
    _visible = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
