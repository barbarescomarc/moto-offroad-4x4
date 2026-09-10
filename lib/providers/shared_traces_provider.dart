import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/shared_trace.dart';
import '../services/shared_traces_api_client.dart';

/// Catalogue des traces partagées, tel que consulté depuis l'onglet Sorties.
///
/// Suit la forme de `FuelPoiProvider` : liste distante, drapeau de
/// chargement, message d'erreur déjà en français et affichable tel quel.
/// Le tri par distance et l'application du rayon sont faits par le serveur
/// à partir de [reference] — le provider ne re-trie jamais lui-même.
///
/// Sans [reference], le serveur ne peut ni trier ni filtrer par rayon : une
/// requête partirait pour rien. `refresh()` pose alors directement le
/// message « Position inconnue » sans toucher au réseau, plutôt que de
/// laisser l'appelant découvrir l'échec après coup.
class SharedTracesProvider extends ChangeNotifier {
  SharedTracesProvider(this._api);

  final SharedTracesApiClient _api;

  List<SharedTraceSummary> _traces = const [];
  bool _isLoading = false;
  String? _error;
  LatLng? _reference;
  String? _referenceLabel;
  double _radiusKm = 50;
  TraceVehicle? _vehicle;
  TraceDifficulty? _difficulty;
  String _query = '';

  List<SharedTraceSummary> get traces => _traces;
  bool get isLoading => _isLoading;
  String? get error => _error;
  LatLng? get reference => _reference;
  String? get referenceLabel => _referenceLabel;
  double get radiusKm => _radiusKm;
  TraceVehicle? get vehicle => _vehicle;
  TraceDifficulty? get difficulty => _difficulty;
  String get query => _query;

  Future<void> setReference(LatLng point, {String? label}) {
    _reference = point;
    _referenceLabel = label;
    return refresh();
  }

  Future<void> setRadius(double km) {
    _radiusKm = km;
    return refresh();
  }

  Future<void> setVehicle(TraceVehicle? vehicle) {
    _vehicle = vehicle;
    return refresh();
  }

  Future<void> setDifficulty(TraceDifficulty? difficulty) {
    _difficulty = difficulty;
    return refresh();
  }

  Future<void> setQuery(String query) {
    _query = query;
    return refresh();
  }

  /// Relance la recherche depuis le début (page 0).
  Future<void> refresh() => _load(offset: 0, append: false);

  /// Charge la page suivante à la suite de [traces], sans rien effacer.
  Future<void> loadMore() => _load(offset: _traces.length, append: true);

  Future<void> _load({required int offset, required bool append}) async {
    final reference = _reference;
    if (reference == null) {
      _error = 'Position inconnue';
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final resultats = await _api.list(
        lat: reference.latitude,
        lng: reference.longitude,
        radiusKm: _radiusKm,
        vehicle: _vehicle,
        difficulty: _difficulty,
        query: _query.isEmpty ? null : _query,
        offset: offset,
      );
      _traces = append ? [..._traces, ...resultats] : resultats;
      _error = null;
    } on SharedTracesException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Réseau indisponible';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
