import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/aire.dart';
import '../services/aires_api_client.dart';
import '../services/aires_cache.dart';

/// D'où viennent les aires affichées, pour que l'écran puisse le dire.
enum OrigineAires { reseau, cache, aucune }

/// Les aires de camping-car autour du pilote.
///
/// Réseau d'abord, cache ensuite. Jamais l'inverse : une aire fermée ou un
/// tarif changé doivent pouvoir arriver. Mais un serveur injoignable ne vide
/// pas la carte — c'est justement en zone blanche qu'on cherche une aire.
class AiresProvider extends ChangeNotifier {
  AiresProvider({AiresApiClient? client, AiresCache? cache})
      : _client = client ?? AiresApiClient(),
        _cache = cache ?? AiresCache();

  final AiresApiClient _client;
  final AiresCache _cache;

  List<AireModel> _aires = const [];
  List<AireModel> get aires => _aires;

  bool _chargement = false;
  bool get chargement => _chargement;

  OrigineAires _origine = OrigineAires.aucune;
  OrigineAires get origine => _origine;

  DateTime? _cacheDate;
  DateTime? get cacheDate => _cacheDate;

  String? _erreur;
  String? get erreur => _erreur;

  bool _visible = true;
  bool get visible => _visible;

  void basculerVisibilite() {
    _visible = !_visible;
    notifyListeners();
  }

  /// Charge le rectangle affiché.
  ///
  /// Le rectangle est élargi d'une marge : sans elle, le moindre glissement
  /// de carte laisserait un bord sans aires, et redemanderait au serveur à
  /// chaque pixel parcouru.
  Future<void> charger({
    required LatLng centre,
    double demiCoteDegres = 0.35,
  }) async {
    final sud = (centre.latitude - demiCoteDegres).clamp(-90.0, 90.0);
    final nord = (centre.latitude + demiCoteDegres).clamp(-90.0, 90.0);
    final ouest = (centre.longitude - demiCoteDegres).clamp(-180.0, 180.0);
    final est = (centre.longitude + demiCoteDegres).clamp(-180.0, 180.0);

    _chargement = true;
    _erreur = null;
    notifyListeners();

    try {
      final recues = await _client.dansRectangle(
          sud: sud, ouest: ouest, nord: nord, est: est);
      _aires = recues;
      _origine = OrigineAires.reseau;
      _cacheDate = DateTime.now();
      // L'écriture du cache ne doit pas faire échouer un affichage réussi :
      // le pilote a ses aires à l'écran, un disque plein est un problème de
      // la prochaine fois.
      try {
        await _cache.remplacerZone(
            sud: sud, ouest: ouest, nord: nord, est: est, aires: recues);
      } catch (_) {}
    } on AiresIndisponibles catch (e) {
      final gardees = await _lireCache(sud, ouest, nord, est);
      _aires = gardees;
      _origine = gardees.isEmpty ? OrigineAires.aucune : OrigineAires.cache;
      _cacheDate = await _cacheDateOuNull(sud, ouest, nord, est);
      _erreur = gardees.isEmpty ? 'Aucune aire : ${e.message}' : null;
    } finally {
      _chargement = false;
      notifyListeners();
    }
  }

  Future<List<AireModel>> _lireCache(double sud, double ouest, double nord, double est) async {
    try {
      return await _cache.dansRectangle(sud: sud, ouest: ouest, nord: nord, est: est);
    } catch (_) {
      return const [];
    }
  }

  Future<DateTime?> _cacheDateOuNull(double sud, double ouest, double nord, double est) async {
    try {
      return await _cache.chargeeLe(sud: sud, ouest: ouest, nord: nord, est: est);
    } catch (_) {
      return null;
    }
  }

  /// Applique localement un relevé accepté par le serveur, pour que la fiche
  /// se mette à jour sans attendre un rechargement complet.
  void appliquerReleve(String aireId, ChampAire champ, Object valeur) {
    _aires = _aires.map((a) => a.id == aireId ? _avecChamp(a, champ, valeur) : a).toList();
    notifyListeners();
  }

  AireModel _avecChamp(AireModel aire, ChampAire champ, Object valeur) {
    switch (champ) {
      case ChampAire.maxHeightM:
        return _copie(aire, maxHeightM: (valeur as num).toDouble());
      case ChampAire.maxLengthM:
        return _copie(aire, maxLengthM: (valeur as num).toDouble());
      case ChampAire.capacity:
        return _copie(aire, capacity: (valeur as num).toInt());
      case ChampAire.priceText:
        return _copie(aire, priceText: '$valeur');
      case ChampAire.openingHours:
        return _copie(aire, openingHours: '$valeur');
    }
  }

  AireModel _copie(
    AireModel a, {
    double? maxHeightM,
    double? maxLengthM,
    int? capacity,
    String? priceText,
    String? openingHours,
  }) =>
      AireModel(
        id: a.id,
        position: a.position,
        source: a.source,
        name: a.name,
        description: a.description,
        services: a.services,
        priceText: priceText ?? a.priceText,
        priceEur: a.priceEur,
        capacity: capacity ?? a.capacity,
        maxHeightM: maxHeightM ?? a.maxHeightM,
        maxLengthM: maxLengthM ?? a.maxLengthM,
        openingHours: openingHours ?? a.openingHours,
        phone: a.phone,
        website: a.website,
        updatedAt: a.updatedAt,
      );
}
