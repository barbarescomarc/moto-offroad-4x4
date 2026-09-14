// test/services/routing_gabarit_test.dart
//
// Le gabarit du camping-car jusque dans la requête d'itinéraire. Ces
// vérifications ne sont pas cosmétiques : un gabarit perdu en chemin envoie
// un 3,20 m sous un pont de 2,80 m.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/vehicle_kind.dart';
import 'package:moto_offroad/services/routing_service.dart';

const _reponseOrs = '''
{
  "features": [
    {
      "geometry": {"coordinates": [[6.0, 44.0], [6.01, 44.01]]},
      "properties": {
        "summary": {"distance": 1500.0, "duration": 300.0},
        "segments": [
          {
            "distance": 1500.0,
            "duration": 300.0,
            "steps": [
              {"distance": 1500.0, "duration": 300.0, "type": 11, "instruction": "Partez", "way_points": [0, 1]}
            ]
          }
        ]
      }
    }
  ]
}
''';

const _depart = LatLng(44.0, 6.0);
const _arrivee = LatLng(44.01, 6.01);

const _profile = GabaritVehicule(hauteurM: 3.2, longueurM: 7.4, poidsT: 3.5);

/// Rend le service et un accès au corps de la dernière requête envoyée.
(RoutingService, Map<String, dynamic> Function(), Uri Function()) _espion() {
  var corps = <String, dynamic>{};
  Uri? url;
  final service = RoutingService(
    client: MockClient((requete) async {
      corps = jsonDecode(requete.body) as Map<String, dynamic>;
      url = requete.url;
      return http.Response(_reponseOrs, 200);
    }),
  );
  return (service, () => corps, () => url!);
}

void main() {
  group('le gabarit part avec la demande d itinéraire', () {
    test('hauteur, longueur et poids sont transmis en restrictions', () async {
      final (service, corps, _) = _espion();

      await service.fetchRoute(
        origin: _depart,
        destination: _arrivee,
        profile: RoutingProfile.drivingHgv,
        gabarit: _profile,
      );

      final options = corps()['options'] as Map<String, dynamic>;
      final restrictions =
          (options['profile_params'] as Map<String, dynamic>)['restrictions']
              as Map<String, dynamic>;
      expect(restrictions['height'], 3.2);
      expect(restrictions['length'], 7.4);
      expect(restrictions['weight'], 3.5);
      expect(options['vehicle_type'], 'hgv');
    });

    test('le camping-car passe par le profil poids lourd', () async {
      final (service, _, url) = _espion();

      await service.fetchRoute(
        origin: _depart,
        destination: _arrivee,
        profile: RoutingProfile.drivingHgv,
        gabarit: _profile,
      );

      expect(url().path, contains('driving-hgv'));
    });

    test('le gabarit n est pas joint à un profil qui le refuserait', () async {
      final (service, corps, _) = _espion();

      await service.fetchRoute(
        origin: _depart,
        destination: _arrivee,
        profile: RoutingProfile.drivingCar,
        gabarit: _profile,
      );

      // ORS rejette la requête entière si `profile_params` accompagne
      // `driving-car` : un guidage refusé est pire qu'un guidage non restreint.
      expect(corps().containsKey('options'), isFalse);
    });

    test('gabarit et évitements cohabitent sous options', () async {
      final (service, corps, _) = _espion();

      await service.fetchRoute(
        origin: _depart,
        destination: _arrivee,
        profile: RoutingProfile.drivingHgv,
        gabarit: _profile,
        avoid: {AvoidFeature.tollways, AvoidFeature.ferries},
      );

      // Les deux logent sous la même clé : l'un écrasait l'autre si le corps
      // était construit par affectation plutôt que par accumulation.
      final options = corps()['options'] as Map<String, dynamic>;
      expect(options['avoid_features'], containsAll(['tollways', 'ferries']));
      expect(options['profile_params'], isNotNull);
    });

    test('sans gabarit, rien n est ajouté au corps', () async {
      final (service, corps, _) = _espion();

      await service.fetchRoute(
        origin: _depart,
        destination: _arrivee,
        profile: RoutingProfile.drivingCar,
      );

      expect(corps().containsKey('options'), isFalse);
    });

    test('les itinéraires alternatifs emportent aussi le gabarit', () async {
      final (service, corps, _) = _espion();

      await service.fetchRouteAlternatives(
        origin: _depart,
        destination: _arrivee,
        profile: RoutingProfile.drivingHgv,
        gabarit: _profile,
      );

      // La préférence « routes sinueuses » passe par ce chemin : elle ne doit
      // pas être une porte de sortie du gabarit.
      final options = corps()['options'] as Map<String, dynamic>;
      expect(options['profile_params'], isNotNull);
    });

    test('un tracé à main levée emporte aussi le gabarit', () async {
      final (service, corps, _) = _espion();

      await service.fetchMultiPointRoute(
        waypoints: const [_depart, LatLng(44.005, 6.005), _arrivee],
        profile: RoutingProfile.drivingHgv,
        gabarit: _profile,
      );

      final options = corps()['options'] as Map<String, dynamic>;
      expect(options['profile_params'], isNotNull);
    });
  });

  group('le profil sait ce qu il est', () {
    test('le poids lourd suit la route, comme la voiture', () {
      // Décide du seuil de sortie d'itinéraire : sans cela, un camping-car
      // hériterait de la tolérance tout-terrain et serait recalculé trop tard.
      expect(RoutingProfile.drivingHgv.suitLaRoute, isTrue);
      expect(RoutingProfile.drivingCar.suitLaRoute, isTrue);
      expect(RoutingProfile.cyclingMountain.suitLaRoute, isFalse);
    });

    test('seul le poids lourd accepte un gabarit', () {
      expect(RoutingProfile.drivingHgv.accepteGabarit, isTrue);
      expect(RoutingProfile.drivingCar.accepteGabarit, isFalse);
      expect(RoutingProfile.cyclingMountain.accepteGabarit, isFalse);
    });
  });

  group('le gabarit vient des réglages', () {
    test('deux gabarits identiques se valent', () {
      expect(
        const GabaritVehicule(hauteurM: 2.8, longueurM: 6.0, poidsT: 3.5),
        const GabaritVehicule(hauteurM: 2.8, longueurM: 6.0, poidsT: 3.5),
      );
    });

    test('les unités sont celles de la carte grise', () {
      const g = GabaritVehicule(hauteurM: 2.85, longueurM: 6.4, poidsT: 3.5);
      expect(g.restrictionsOrs, {'height': 2.85, 'length': 6.4, 'weight': 3.5});
    });
  });
}
