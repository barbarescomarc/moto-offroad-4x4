// test/widgets/alerte_groupe_banner_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/providers/group_provider.dart';
import 'package:moto_offroad/services/tracker_api_client.dart';
import 'package:moto_offroad/widgets/alerte_groupe_banner.dart';
import 'package:provider/provider.dart';

/// Groupe dont l'alerte et l'identité sont posées à la main, sans réseau.
class _GroupeFictif extends GroupProvider {
  _GroupeFictif({required this.alerteCourante, required this.jeSuisLauteur});

  AlerteGroupe? alerteCourante;
  bool jeSuisLauteur;
  bool masquee = false;

  @override
  AlerteGroupe? get alerteAafficher => masquee ? null : alerteCourante;

  @override
  bool get jeSuisLauteurDeLalerte => jeSuisLauteur;

  @override
  void masquerAlerte() {
    masquee = true;
    notifyListeners();
  }
}

AlerteGroupe _alerte({String kind = 'sos', LatLng? position}) => AlerteGroupe(
      memberId: 'm1',
      name: 'Marc',
      kind: kind,
      raisedAt: DateTime(2026, 9, 14, 15, 42),
      position: position,
    );

Widget _monter(
  _GroupeFictif groupe, {
  LatLng? maPosition,
  void Function(LatLng)? onYAller,
}) =>
    ChangeNotifierProvider<GroupProvider>.value(
      value: groupe,
      child: MaterialApp(
        home: Scaffold(
          body: AlerteGroupeBanner(
            maPosition: () => maPosition,
            onYAller: onYAller,
          ),
        ),
      ),
    );

void main() {
  testWidgets('sans alerte, rien ne s affiche', (tester) async {
    await tester.pumpWidget(
      _monter(_GroupeFictif(alerteCourante: null, jeSuisLauteur: false)),
    );

    expect(find.byKey(const Key('alerte-groupe')), findsNothing);
  });

  testWidgets('nomme le rider et le genre de l alerte', (tester) async {
    await tester.pumpWidget(_monter(
      _GroupeFictif(alerteCourante: _alerte(kind: 'fall'), jeSuisLauteur: false),
    ));

    expect(find.textContaining('Marc'), findsOneWidget);
    expect(find.textContaining('chute détectée'), findsOneWidget);
  });

  testWidgets('donne la distance et le cap quand les deux positions sont connues',
      (tester) async {
    await tester.pumpWidget(_monter(
      _GroupeFictif(
        alerteCourante: _alerte(position: const LatLng(42.75, 1.98)),
        jeSuisLauteur: false,
      ),
      maPosition: const LatLng(42.74, 1.98),
    ));

    // Environ 1,1 km plein nord. Le cap se lit en points cardinaux : on lit
    // ça avec des gants, casque sur la tête.
    expect(find.textContaining('km'), findsOneWidget);
    expect(find.textContaining('vers le nord'), findsOneWidget);
  });

  testWidgets('avoue quand la position du rider est inconnue', (tester) async {
    await tester.pumpWidget(_monter(
      _GroupeFictif(alerteCourante: _alerte(position: null), jeSuisLauteur: false),
      maPosition: const LatLng(42.74, 1.98),
    ));

    // Un bandeau muet sur la position laisserait croire qu'on cherche au bon
    // endroit.
    expect(find.textContaining('Position inconnue'), findsOneWidget);
    expect(find.byKey(const Key('alerte-groupe-y-aller')), findsNothing);
  });

  testWidgets('propose d y aller quand on sait où', (tester) async {
    LatLng? cibleDemandee;
    await tester.pumpWidget(_monter(
      _GroupeFictif(
        alerteCourante: _alerte(position: const LatLng(42.75, 1.98)),
        jeSuisLauteur: false,
      ),
      maPosition: const LatLng(42.74, 1.98),
      onYAller: (c) => cibleDemandee = c,
    ));

    await tester.tap(find.byKey(const Key('alerte-groupe-y-aller')));
    await tester.pump();

    expect(cibleDemandee, const LatLng(42.75, 1.98));
  });

  testWidgets('masquer retire le bandeau de cet écran seulement', (tester) async {
    final groupe = _GroupeFictif(alerteCourante: _alerte(), jeSuisLauteur: false);
    await tester.pumpWidget(_monter(groupe));

    await tester.tap(find.byKey(const Key('alerte-groupe-masquer')));
    await tester.pump();

    expect(find.byKey(const Key('alerte-groupe')), findsNothing);
    // Masquer n'est pas retirer : l'appel à l'aide tient toujours pour les
    // autres riders.
    expect(groupe.alerteCourante, isNotNull);
  });

  testWidgets('l auteur voit que son appel est parti, et peut le retirer',
      (tester) async {
    await tester.pumpWidget(_monter(
      _GroupeFictif(alerteCourante: _alerte(), jeSuisLauteur: true),
    ));

    expect(find.textContaining('Ton alerte est partie'), findsOneWidget);
    expect(find.byKey(const Key('alerte-groupe-je-vais-bien')), findsOneWidget);
    // Lui seul : les autres ne savent pas s'il va bien.
    expect(find.byKey(const Key('alerte-groupe-masquer')), findsNothing);
  });

  testWidgets('les commandes restent touchables sur écran étroit', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_monter(
      _GroupeFictif(
        alerteCourante: _alerte(position: const LatLng(42.75, 1.98)),
        jeSuisLauteur: false,
      ),
      maPosition: const LatLng(42.74, 1.98),
      onYAller: (_) {},
    ));

    // Le thème impose Size(double.infinity, 52) à tout ElevatedButton : deux
    // boutons sur une même ligne devenaient intouchables (voir le bouton
    // « Suivant » du tutoriel, même piège).
    final bouton = tester.getRect(find.byKey(const Key('alerte-groupe-y-aller')));
    expect(bouton.width, lessThan(320));
    expect(bouton.height, greaterThanOrEqualTo(44));
  });
}
