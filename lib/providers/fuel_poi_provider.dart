import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/poi.dart';
import '../models/vehicle_kind.dart';
import '../services/fuel_poi_service.dart';

/// Les points d'appui du véhicule autour du pilote.
///
/// `unavailable` est distinct d'une liste vide : « aucune station dans ce
/// rayon » et « je n'ai pas pu joindre Overpass » n'appellent pas la même
/// conduite — la première fait élargir le rayon, la seconde fait réessayer.
class FuelPoiProvider extends ChangeNotifier {
  FuelPoiProvider({FuelPoiService? service}) : _service = service ?? FuelPoiService();

  final FuelPoiService _service;

  static const _kMasquees = 'poi_categories_masquees';

  List<PoiModel> _results = const [];
  bool _loading = false;
  bool _unavailable = false;
  bool _visible = false;

  /// Les catégories que le pilote ne veut pas voir.
  ///
  /// Stocké en négatif — ce qu'on masque plutôt que ce qu'on montre — pour
  /// qu'une catégorie ajoutée plus tard à un véhicule s'affiche d'office :
  /// une liste de catégories visibles enregistrée l'an dernier ferait
  /// disparaître silencieusement la nouveauté.
  Set<PoiCategory> _masquees = <PoiCategory>{};

  /// Tout ce qui a été trouvé, filtres compris. Sert à savoir quelles puces
  /// proposer : on ne propose de filtrer que ce qui a été réellement trouvé.
  List<PoiModel> get results => _results;

  /// Ce que la carte doit afficher, une fois les filtres appliqués.
  List<PoiModel> get resultatsFiltres =>
      _results.where((p) => !_masquees.contains(p.category)).toList();

  /// Les catégories présentes dans les résultats, dans l'ordre du modèle.
  List<PoiCategory> get categoriesTrouvees {
    final presentes = _results.map((p) => p.category).toSet();
    return PoiCategory.values.where(presentes.contains).toList();
  }

  bool estAffichee(PoiCategory categorie) => !_masquees.contains(categorie);

  int compte(PoiCategory categorie) =>
      _results.where((p) => p.category == categorie).length;
  bool get loading => _loading;
  bool get unavailable => _unavailable;

  /// Les résultats sont-ils affichés sur la carte ?
  ///
  /// Distinct de « y a-t-il des résultats » : masquer n'est pas oublier. Le
  /// pilote qui éteint puis rallume doit les revoir instantanément, sans
  /// qu'on redemande à Overpass — service public, gratuit et irrégulier.
  bool get visible => _visible;

  Future<void> searchAround(
    LatLng center, {
    required int radiusKm,
    VehicleKind vehicule = VehicleKind.moto,
  }) async {
    _loading = true;
    notifyListeners();

    try {
      _results = await _service.fetchAround(center, radiusKm: radiusKm, vehicule: vehicule);
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

  /// Relit les filtres persistés. Appelé au démarrage de l'application.
  Future<void> chargerFiltres() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final noms = prefs.getStringList(_kMasquees) ?? const [];
      _masquees = noms
          .map((n) => PoiCategory.values.where((c) => c.name == n).firstOrNull)
          .whereType<PoiCategory>()
          .toSet();
      notifyListeners();
    } catch (_) {
      // Un stockage indisponible ne doit pas empêcher la recherche : sans
      // filtre lu, on affiche tout, ce qui est le comportement par défaut.
    }
  }

  /// Affiche ou masque une catégorie. Le choix survit au redémarrage : c'est
  /// une préférence, pas un réglage d'un après-midi.
  Future<void> basculerCategorie(PoiCategory categorie) async {
    if (_masquees.contains(categorie)) {
      _masquees.remove(categorie);
    } else {
      _masquees.add(categorie);
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kMasquees, _masquees.map((c) => c.name).toList());
    } catch (_) {}
  }

  /// Remet tout à l'affichage.
  Future<void> toutAfficher() async {
    if (_masquees.isEmpty) return;
    _masquees = <PoiCategory>{};
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kMasquees, const []);
    } catch (_) {}
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
