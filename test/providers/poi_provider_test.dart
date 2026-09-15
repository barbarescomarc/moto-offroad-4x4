// test/providers/poi_provider_test.dart
//
// Un seul écran, trois sources. Le pilote coche ce qu'il veut voir ; c'est
// le fournisseur qui sait où chaque catégorie se demande, et qui recolle les
// réponses en une seule liste.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/models/poi.dart';
import 'package:moto_offroad/models/vehicle_kind.dart';
import 'package:moto_offroad/providers/poi_provider.dart';
import 'package:moto_offroad/services/data_tourisme_service.dart';
import 'package:moto_offroad/services/fuel_poi_service.dart';

const _ici = LatLng(44.5, 6.5);

PoiModel _poi(String nom, PoiCategory c) =>
    PoiModel(id: nom, name: nom, category: c, position: _ici);

class _OverpassFactice extends FuelPoiService {
  _OverpassFactice({this.retour = const [], this.panne = false});
  final List<PoiModel> retour;
  final bool panne;
  int appels = 0;
  VehicleKind? dernierVehicule;

  @override
  Future<List<PoiModel>> fetchAround(LatLng center,
      {required int radiusKm, VehicleKind vehicule = VehicleKind.moto}) async {
    appels++;
    dernierVehicule = vehicule;
    if (panne) throw const FuelPoiUnavailable();
    return retour;
  }
}

class _TourismeFactice extends DataTourismeService {
  _TourismeFactice({this.retour = const []});
  final List<PoiModel> retour;
  int appelsAutour = 0, appelsLeLong = 0;
  Set<PoiCategory>? dernieresCategories;

  @override
  Future<List<PoiModel>> searchAround(LatLng point,
      {required double radiusKm, required Set<PoiCategory> categories}) async {
    appelsAutour++;
    dernieresCategories = categories;
    return retour;
  }

  @override
  Future<List<PoiModel>> searchAlongRoute(List<LatLng> polyline,
      {required double radiusKm, required Set<PoiCategory> categories}) async {
    appelsLeLong++;
    dernieresCategories = categories;
    return retour;
  }
}

Future<PoiProvider> _fournisseur({
  _OverpassFactice? overpass,
  _TourismeFactice? tourisme,
}) async {
  final p = PoiProvider(
    overpass: overpass ?? _OverpassFactice(),
    tourisme: tourisme ?? _TourismeFactice(),
  );
  await p.charger();
  return p;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('une recherche pose les resultats et retombe le chargement', () async {
    final overpass = _OverpassFactice(retour: [_poi('Total', PoiCategory.gasStation)]);
    final p = await _fournisseur(overpass: overpass);
    await p.basculer(PoiCategory.gasStation);

    await p.chercher(autour: _ici, vehicule: VehicleKind.moto);

    expect(p.resultats, hasLength(1));
    expect(p.enCours, isFalse);
    expect(p.indisponible, isFalse);
  });

  test('une panne signale l indisponibilite plutot que zero resultat', () async {
    final p = await _fournisseur(overpass: _OverpassFactice(panne: true));
    await p.basculer(PoiCategory.gasStation);

    await p.chercher(autour: _ici, vehicule: VehicleKind.moto);

    expect(p.indisponible, isTrue,
        reason: 'zéro station et un service muet ne se disent pas pareil');
  });

  test('une recherche reussie efface une indisponibilite precedente', () async {
    final p = await _fournisseur(overpass: _OverpassFactice(panne: true));
    await p.basculer(PoiCategory.gasStation);
    await p.chercher(autour: _ici, vehicule: VehicleKind.moto);
    expect(p.indisponible, isTrue);

    final repare = await _fournisseur(
        overpass: _OverpassFactice(retour: [_poi('Total', PoiCategory.gasStation)]));
    await repare.basculer(PoiCategory.gasStation);
    await repare.chercher(autour: _ici, vehicule: VehicleKind.moto);
    expect(repare.indisponible, isFalse);
  });

  test('seules les categories cochees sortent d Overpass', () async {
    // Overpass rapporte tout ce que le véhicule peut vouloir : c'est au
    // fournisseur d'écarter ce qui n'a pas été coché.
    final overpass = _OverpassFactice(retour: [
      _poi('Total', PoiCategory.gasStation),
      _poi('Garage Dupont', PoiCategory.garage),
    ]);
    final p = await _fournisseur(overpass: overpass);
    await p.basculer(PoiCategory.gasStation);

    await p.chercher(autour: _ici, vehicule: VehicleKind.quatreQuatre);

    expect(p.resultats.map((r) => r.category), [PoiCategory.gasStation]);
  });

  test('les deux sources se rejoignent en une seule liste', () async {
    final p = await _fournisseur(
      overpass: _OverpassFactice(retour: [_poi('Total', PoiCategory.gasStation)]),
      tourisme: _TourismeFactice(retour: [_poi('Belvédère', PoiCategory.viewpoint)]),
    );
    await p.basculer(PoiCategory.gasStation);
    await p.basculer(PoiCategory.viewpoint);

    await p.chercher(autour: _ici, vehicule: VehicleKind.moto);

    expect(p.resultats, hasLength(2));
  });

  test('aucune source n est derangee sans categorie de son ressort', () async {
    final overpass = _OverpassFactice();
    final tourisme = _TourismeFactice();
    final p = await _fournisseur(overpass: overpass, tourisme: tourisme);
    await p.basculer(PoiCategory.viewpoint);

    await p.chercher(autour: _ici, vehicule: VehicleKind.moto);

    expect(tourisme.appelsAutour, 1);
    expect(overpass.appels, 0, reason: 'aucune catégorie pratique cochée');
  });

  test('le long de la route n interroge que le tourisme', () async {
    // Overpass ne sait pas chercher le long d'un tracé : lui demander autour
    // d'un point arbitraire donnerait des stations hors sujet.
    final overpass = _OverpassFactice();
    final tourisme = _TourismeFactice();
    final p = await _fournisseur(overpass: overpass, tourisme: tourisme);
    await p.basculer(PoiCategory.gasStation);
    await p.basculer(PoiCategory.viewpoint);

    await p.chercher(leLongDe: const [_ici, LatLng(44.6, 6.6)], vehicule: VehicleKind.moto);

    expect(tourisme.appelsLeLong, 1);
    expect(overpass.appels, 0);
  });

  test('sans point ni trace, rien ne part et rien ne plante', () async {
    final overpass = _OverpassFactice();
    final tourisme = _TourismeFactice();
    final p = await _fournisseur(overpass: overpass, tourisme: tourisme);
    await p.basculer(PoiCategory.gasStation);

    await p.chercher(vehicule: VehicleKind.moto);

    expect(p.resultats, isEmpty);
    expect(overpass.appels, 0);
    expect(tourisme.appelsAutour, 0);
  });

  test('la selection et le rayon survivent au redemarrage', () async {
    final p = await _fournisseur();
    await p.basculer(PoiCategory.viewpoint);
    await p.setRayonKm(35);

    final relu = await _fournisseur();
    expect(relu.selection, contains(PoiCategory.viewpoint));
    expect(relu.rayonKm, 35);
  });

  test('le rayon voyage jusqu aux deux services', () async {
    final overpass = _OverpassFactice();
    final tourisme = _TourismeFactice();
    final p = await _fournisseur(overpass: overpass, tourisme: tourisme);
    await p.basculer(PoiCategory.gasStation);
    await p.basculer(PoiCategory.viewpoint);
    await p.setRayonKm(12);

    await p.chercher(autour: _ici, vehicule: VehicleKind.moto);

    expect(p.rayonKm, 12);
    expect(tourisme.appelsAutour, 1);
    expect(overpass.appels, 1);
  });

  group('proposer « Chercher ici »', () {
    test('jamais sans rien de coche', () async {
      final p = await _fournisseur();
      expect(p.proposerIci(const LatLng(45.0, 7.0), positionPilote: _ici), isFalse);
    });

    test('pas tant qu on regarde la zone deja cherchee', () async {
      final p = await _fournisseur(
          overpass: _OverpassFactice(retour: [_poi('Total', PoiCategory.gasStation)]));
      await p.basculer(PoiCategory.gasStation);
      await p.chercher(autour: _ici, vehicule: VehicleKind.moto);

      // 300 m plus loin : c'est la même zone.
      expect(p.proposerIci(const LatLng(44.5027, 6.5)), isFalse);
    });

    test('des qu on s eloigne de ce qu on a cherche', () async {
      final p = await _fournisseur(
          overpass: _OverpassFactice(retour: [_poi('Total', PoiCategory.gasStation)]));
      await p.basculer(PoiCategory.gasStation);
      await p.chercher(autour: _ici, vehicule: VehicleKind.moto);

      expect(p.proposerIci(const LatLng(44.6, 6.6)), isTrue);
    });

    test('avant toute recherche, on se repere sur le pilote', () async {
      final p = await _fournisseur();
      await p.basculer(PoiCategory.gasStation);
      expect(p.proposerIci(_ici, positionPilote: _ici), isFalse);
      expect(p.proposerIci(const LatLng(44.6, 6.6), positionPilote: _ici), isTrue);
    });
  });

  test('effacer vide la carte sans oublier la selection', () async {
    final p = await _fournisseur(
        overpass: _OverpassFactice(retour: [_poi('Total', PoiCategory.gasStation)]));
    await p.basculer(PoiCategory.gasStation);
    await p.chercher(autour: _ici, vehicule: VehicleKind.moto);

    p.effacer();

    expect(p.resultats, isEmpty);
    expect(p.selection, contains(PoiCategory.gasStation),
        reason: 'effacer la carte n est pas décocher');
  });
}
