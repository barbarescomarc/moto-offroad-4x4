import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/poi.dart';
import '../models/vehicle_kind.dart';
import '../services/data_tourisme_service.dart';
import '../services/fuel_poi_service.dart';

/// Ce que le pilote veut voir autour de lui — une seule liste, une seule
/// feuille, un seul calque sur la carte.
///
/// Il y avait deux chaînes séparées : le tourisme (DATAtourisme) derrière un
/// appui court, le pratique (OpenStreetMap) derrière un appui long, chacune
/// avec sa feuille et ses filtres. Deux écrans pour une seule question :
/// « qu'est-ce qu'il y a autour ? ». Elles se rejoignent ici.
///
/// Les aires de camping-car ne sont pas de la partie : elles ont leur propre
/// chaîne, servie par le serveur GO FREE avec la hauteur limite et les
/// relevés des autres pilotes — voir AiresProvider. La feuille les propose
/// au même endroit, mais c'est lui qui les sert.
class PoiProvider extends ChangeNotifier {
  PoiProvider({FuelPoiService? overpass, DataTourismeService? tourisme})
      : _overpass = overpass ?? FuelPoiService(),
        _tourisme = tourisme ?? DataTourismeService();

  static const _kSelection = 'poi_selection';
  static const _kRayon     = 'poi_rayon_km';
  static const int rayonParDefautKm = 20;

  final FuelPoiService _overpass;
  final DataTourismeService _tourisme;

  Set<PoiCategory> _selection = {};
  int _rayonKm = rayonParDefautKm;
  List<PoiModel> _resultats = [];
  bool _enCours = false;
  bool _indisponible = false;
  LatLng? _dernierCentre;

  Set<PoiCategory> get selection => Set.unmodifiable(_selection);
  int get rayonKm => _rayonKm;
  List<PoiModel> get resultats => List.unmodifiable(_resultats);
  bool get enCours => _enCours;
  bool get indisponible => _indisponible;

  /// Le point autour duquel la dernière recherche a eu lieu. La carte s'en
  /// sert pour savoir quand proposer « Chercher ici » : tant qu'on regarde
  /// la même zone, la question ne se pose pas.
  LatLng? get dernierCentre => _dernierCentre;

  Future<void> charger() async {
    final prefs = await SharedPreferences.getInstance();
    _selection = (prefs.getStringList(_kSelection) ?? const <String>[])
        .map((n) => PoiCategory.values.where((c) => c.name == n))
        .expand((c) => c)
        .toSet();
    _rayonKm = prefs.getInt(_kRayon) ?? rayonParDefautKm;
    notifyListeners();
  }

  Future<void> basculer(PoiCategory categorie) async {
    if (!_selection.add(categorie)) _selection.remove(categorie);
    // Décocher retire les points de la carte tout de suite : attendre la
    // prochaine recherche laisserait à l'écran ce qu'on vient de refuser.
    _resultats = _resultats.where((p) => _selection.contains(p.category)).toList();
    await _ecrire();
    notifyListeners();
  }

  Future<void> setRayonKm(int km) async {
    _rayonKm = km.clamp(1, 100);
    await _ecrire();
    notifyListeners();
  }

  Future<void> _ecrire() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _kSelection, _selection.map((c) => c.name).toList());
    await prefs.setInt(_kRayon, _rayonKm);
  }

  /// Interroge chaque source pour ce qui la concerne, et recolle.
  ///
  /// `autour` pour une recherche ponctuelle — sa position, ou l'endroit
  /// qu'elle regarde, ou sa destination ; `leLongDe` pour l'itinéraire
  /// entier. Overpass ne sait pas faire le second : lui demander un point
  /// arbitraire rapporterait des stations hors sujet.
  Future<void> chercher({
    LatLng? autour,
    List<LatLng>? leLongDe,
    required VehicleKind vehicule,
  }) async {
    final tourisme = _selection.where((c) => c.vientDuTourisme).toSet();
    final pratique = _selection.where((c) => c.vientDOverpass).toSet();
    if (autour == null && (leLongDe == null || leLongDe.isEmpty)) return;
    if (tourisme.isEmpty && pratique.isEmpty) return;

    _enCours = true;
    notifyListeners();

    final trouves = <PoiModel>[];
    var panne = false;

    if (tourisme.isNotEmpty) {
      try {
        trouves.addAll(leLongDe != null && leLongDe.isNotEmpty
            ? await _tourisme.searchAlongRoute(leLongDe,
                radiusKm: _rayonKm.toDouble(), categories: tourisme)
            : await _tourisme.searchAround(autour!,
                radiusKm: _rayonKm.toDouble(), categories: tourisme));
      } catch (_) {
        panne = true;
      }
    }

    if (pratique.isNotEmpty && autour != null && (leLongDe == null || leLongDe.isEmpty)) {
      try {
        // Overpass répond pour tout ce que le véhicule peut vouloir : on
        // écarte ici ce qui n'a pas été coché.
        final bruts = await _overpass.fetchAround(autour,
            radiusKm: _rayonKm, vehicule: vehicule);
        trouves.addAll(bruts.where((p) => pratique.contains(p.category)));
      } on FuelPoiUnavailable {
        panne = true;
      } catch (_) {
        panne = true;
      }
    }

    _resultats = trouves;
    _dernierCentre = autour ?? leLongDe?.first;
    _indisponible = panne;
    _enCours = false;
    notifyListeners();
  }

  /// Faut-il proposer « Chercher ici » ?
  ///
  /// La question ne se pose que si le pilote a déplacé la carte loin de ce
  /// qu'il a déjà exploré : tant qu'il regarde la zone qu'il vient de
  /// chercher, la pastille n'aurait rien à lui apprendre. Sans sélection,
  /// elle n'aurait rien à chercher non plus.
  bool proposerIci(
    LatLng centreCarte, {
    LatLng? positionPilote,
    double seuilMetres = 1000,
  }) {
    if (_selection.isEmpty || _enCours) return false;
    final reference = _dernierCentre ?? positionPilote;
    if (reference == null) return true;
    return const Distance().as(LengthUnit.Meter, reference, centreCarte) > seuilMetres;
  }

  /// Vide la carte sans toucher à ce qui est coché : on range l'affichage,
  /// on ne renonce pas à ce qu'on cherchait.
  void effacer() {
    _resultats = [];
    _dernierCentre = null;
    _indisponible = false;
    notifyListeners();
  }
}
