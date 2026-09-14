// test/services/alerte_groupe_test.dart
//
// Le SOS atteint les riders de la sortie. Ils sont à quelques centaines de
// mètres quand un contact de confiance est à plusieurs heures de route : ce
// canal est celui par lequel arrive le premier secours.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/providers/solo_provider.dart';
import 'package:moto_offroad/services/fall_alert_service.dart';
import 'package:moto_offroad/services/location_service.dart';

GpsSnapshot _snap() => GpsSnapshot(
      position: const LatLng(42.74, 1.98),
      accuracyMeters: 5,
      altitudeMeters: 1900,
      speedKmh: 0,
      headingDeg: 0,
      timestamp: DateTime.now(),
    );

/// Chaîne d'alerte réduite à ce que le test veut observer.
FallAlertService _chaine({
  SendGroupAlertFn? groupe,
  bool telephone = false,
  bool serveur = false,
  List<TrustedContact> contacts = const [],
}) =>
    FallAlertService(
      sendSms: (_, __) async => true,
      sendServerAlert: ({required kind}) async => true,
      phoneChannelEnabled: () => telephone,
      serverChannelEnabled: () => serveur,
      trustedContacts: () => contacts,
      positionProvider: () async => _snap(),
      sendGroupAlert: groupe,
    );

void main() {
  test('le groupe est prévenu en même temps que les proches', () async {
    String? genreRecu;
    final service = _chaine(
      groupe: ({required kind}) async {
        genreRecu = kind;
        return true;
      },
      telephone: true,
      serveur: true,
      contacts: [
        TrustedContact(
            id: '1', name: 'Claire', phone: '0600000000', email: 'c@x.test', relation: 'Sœur'),
      ],
    );

    final resultat = await service.sendFallAlert(kind: 'sos');

    // « En plus », pas « à la place » : les deux partent, celui qui arrive le
    // premier a gagné.
    expect(genreRecu, 'sos');
    expect(resultat.groupNotified, isTrue);
    expect(resultat.contactsNotified, 1);
    expect(resultat.serverNotified, isTrue);
  });

  test('le canal groupe ne dépend pas des réglages des autres canaux', () async {
    var groupePrevenu = false;
    final service = _chaine(
      groupe: ({required kind}) async {
        groupePrevenu = true;
        return true;
      },
      telephone: false,
      serveur: false,
    );

    final resultat = await service.sendFallAlert(kind: 'fall');

    // Les deux autres canaux se coupent parce qu'ils dérangent des gens loin
    // de la piste. Celui-ci ne dérange que des riders qui roulent avec toi.
    expect(groupePrevenu, isTrue);
    expect(resultat.groupNotified, isTrue);
  });

  test('hors groupe, la chaîne est inchangée', () async {
    final service = _chaine(groupe: null, serveur: true);

    final resultat = await service.sendFallAlert(kind: 'sos');

    expect(resultat.groupNotified, isFalse);
    expect(resultat.serverNotified, isTrue);
  });

  test('un groupe injoignable ne se fait pas passer pour prévenu', () async {
    final service = _chaine(groupe: ({required kind}) async => false);

    final resultat = await service.sendFallAlert(kind: 'sos');

    expect(resultat.groupNotified, isFalse);
  });

  test('aucun canal abouti se dit franchement', () async {
    final service = _chaine(groupe: ({required kind}) async => false);

    final resultat = await service.sendFallAlert(kind: 'sos');

    // L'écran de confirmation ne doit jamais rassurer à tort quelqu'un qui
    // vient de tomber.
    expect(resultat.personneJointe, isTrue);
  });

  test('un seul canal abouti suffit à ne plus être seul', () async {
    final service = _chaine(groupe: ({required kind}) async => true);

    final resultat = await service.sendFallAlert(kind: 'fall');

    expect(resultat.personneJointe, isFalse);
  });
}
