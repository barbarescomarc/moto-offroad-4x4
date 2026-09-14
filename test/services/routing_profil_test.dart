// test/services/routing_profil_test.dart
//
// Quel profil ORS pour quel véhicule. Le choix décide de deux choses qui ne
// se rattrapent pas en route : si le gabarit peut encore être transmis, et si
// l'itinéraire a le droit de quitter le bitume.
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/models/vehicle_kind.dart';
import 'package:moto_offroad/services/routing_service.dart';

void main() {
  group('le camping-car reste sur les routes ouvertes par défaut', () {
    test('en mode route, il passe par le poids lourd', () {
      expect(
        profilItineraire(
          vehicule: VehicleKind.van,
          modeHorsRoute: false,
          autoriseHorsRoute: false,
        ),
        RoutingProfile.drivingHgv,
      );
    });

    test('en mode hors-route non autorisé, il y passe encore', () {
      expect(
        profilItineraire(
          vehicule: VehicleKind.van,
          modeHorsRoute: true,
          autoriseHorsRoute: false,
        ),
        RoutingProfile.drivingHgv,
      );
    });
  });

  group('le fourgon 4x4 a le droit à la piste', () {
    test('hors-route autorisé, le profil montagne prend la main', () {
      expect(
        profilItineraire(
          vehicule: VehicleKind.van,
          modeHorsRoute: true,
          autoriseHorsRoute: true,
        ),
        RoutingProfile.cyclingMountain,
      );
    });

    test('mais le mode route lui rend son gabarit', () {
      expect(
        profilItineraire(
          vehicule: VehicleKind.van,
          modeHorsRoute: false,
          autoriseHorsRoute: true,
        ),
        RoutingProfile.drivingHgv,
      );
    });
  });

  group('les véhicules sans gabarit gardent leur comportement', () {
    test('la moto hors-route prend le profil montagne', () {
      expect(
        profilItineraire(
          vehicule: VehicleKind.moto,
          modeHorsRoute: true,
          autoriseHorsRoute: true,
        ),
        RoutingProfile.cyclingMountain,
      );
    });

    test('la moto sur route prend le profil voiture', () {
      expect(
        profilItineraire(
          vehicule: VehicleKind.moto,
          modeHorsRoute: false,
          autoriseHorsRoute: true,
        ),
        RoutingProfile.drivingCar,
      );
    });

    test('le 4x4 hors-route prend le profil montagne', () {
      expect(
        profilItineraire(
          vehicule: VehicleKind.quatreQuatre,
          modeHorsRoute: true,
          autoriseHorsRoute: true,
        ),
        RoutingProfile.cyclingMountain,
      );
    });
  });

  test('le profil montagne refuse le gabarit, le poids lourd l accepte', () {
    expect(RoutingProfile.cyclingMountain.accepteGabarit, isFalse);
    expect(RoutingProfile.drivingCar.accepteGabarit, isFalse);
    expect(RoutingProfile.drivingHgv.accepteGabarit, isTrue);
  });
}
