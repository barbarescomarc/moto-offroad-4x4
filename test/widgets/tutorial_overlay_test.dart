import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/services/tutorial_controller.dart';
import 'package:moto_offroad/services/tutorial_steps.dart';
import 'package:moto_offroad/widgets/tutorial_overlay.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('la carte affiche le numero d etape et avance au clic', (tester) async {
    final c = TutorialController(targets: TutorialTargets(
      modeSwitch: GlobalKey(), sos: GlobalKey(), recording: GlobalKey(),
      actions: GlobalKey(), layers: GlobalKey(),
    ));
    await c.startIfNeeded();

    await tester.pumpWidget(MaterialApp(home: Stack(children: [TutorialOverlay(controller: c)])));
    expect(find.text('ÉTAPE 1 / 6'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tuto-suivant')));
    await tester.pump();
    expect(find.text('ÉTAPE 2 / 6'), findsOneWidget);
  });

  testWidgets('le bouton passer ferme le tutoriel', (tester) async {
    final c = TutorialController(targets: TutorialTargets(
      modeSwitch: GlobalKey(), sos: GlobalKey(), recording: GlobalKey(),
      actions: GlobalKey(), layers: GlobalKey(),
    ));
    await c.startIfNeeded();
    await tester.pumpWidget(MaterialApp(home: Stack(children: [TutorialOverlay(controller: c)])));

    await tester.tap(find.byKey(const Key('tuto-passer')));
    await tester.pumpAndSettle();
    expect(find.text('ÉTAPE 1 / 6'), findsNothing);
  });

  testWidgets('le voile est opaque aux gestes : rien ne doit filtrer vers la carte en dessous', (tester) async {
    // HitTestBehavior.opaque est ce qui arrête le test de collision au
    // niveau du rendu avant même la carte du dessous : sans lui (translucide
    // ou par défaut), un glissement sur le voile atteindrait le
    // gestionnaire de la carte et la ferait bouger pendant le tutoriel.
    final c = TutorialController(targets: TutorialTargets(
      modeSwitch: GlobalKey(), sos: GlobalKey(), recording: GlobalKey(),
      actions: GlobalKey(), layers: GlobalKey(),
    ));
    await c.startIfNeeded();
    await tester.pumpWidget(MaterialApp(home: Stack(children: [TutorialOverlay(controller: c)])));

    final voile = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_SpotlightPainter',
    );
    expect(voile, findsOneWidget);
    final geste = tester.widget<GestureDetector>(
      find.ancestor(of: voile, matching: find.byType(GestureDetector)).first,
    );
    expect(geste.behavior, HitTestBehavior.opaque);
  });

  testWidgets('la derniere etape affiche Terminer et ferme le tutoriel', (tester) async {
    final c = TutorialController(targets: TutorialTargets(
      modeSwitch: GlobalKey(), sos: GlobalKey(), recording: GlobalKey(),
      actions: GlobalKey(), layers: GlobalKey(),
    ));
    await c.startIfNeeded();
    for (var i = 0; i < 5; i++) {
      c.next();
    }
    await tester.pumpWidget(MaterialApp(home: Stack(children: [TutorialOverlay(controller: c)])));
    expect(find.text('ÉTAPE 6 / 6'), findsOneWidget);
    expect(find.text('Terminer ✓'), findsOneWidget);
    expect(find.text('Suivant'), findsNothing);

    await tester.tap(find.byKey(const Key('tuto-suivant')));
    await tester.pumpAndSettle();
    expect(find.text('ÉTAPE 6 / 6'), findsNothing);
  });

  testWidgets('la carte reste utilisable sur un ecran bas et large, comme en paysage', (tester) async {
    // Une rotation peut survenir pendant le tutoriel (OrientationBuilder
    // rebascule en direct entre portrait et paysage) : la carte, épinglée
    // en bas avec une hauteur maximale, doit rester lisible et son pied
    // (les boutons) doit rester atteignable même sur un écran bas et large.
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const taille = Size(800, 400);
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1.0;

    final c = TutorialController(targets: TutorialTargets(
      modeSwitch: GlobalKey(), sos: GlobalKey(), recording: GlobalKey(),
      actions: GlobalKey(), layers: GlobalKey(),
    ));
    await c.startIfNeeded();
    await tester.pumpWidget(MaterialApp(home: Stack(children: [TutorialOverlay(controller: c)])));

    expect(find.text('ÉTAPE 1 / 6'), findsOneWidget);
    final suivantRect = tester.getRect(find.byKey(const Key('tuto-suivant')));
    expect(suivantRect.bottom, lessThanOrEqualTo(taille.height),
        reason: 'le bouton Suivant doit rester dans les limites de l ecran');
    expect(suivantRect.top, greaterThanOrEqualTo(0));

    await tester.tap(find.byKey(const Key('tuto-suivant')));
    await tester.pump();
    expect(find.text('ÉTAPE 2 / 6'), findsOneWidget);
  });

  // Regression du 2026-09-13 : « Suivant » etait intouchable, seul « Passer »
  // repondait — le tutoriel ne pouvait pas se derouler.
  //
  // Les commandes vivaient dans un Row de largeur fixe. Des que la somme des
  // boutons depassait la carte — ce qu une taille de police systeme agrandie
  // suffit a provoquer — le Row debordait par la droite, et Flutter clippe ce
  // qui deborde : le dernier enfant, « Suivant », sortait de la zone
  // touchable. « Passer », premier enfant, restait lui toujours atteignable.
  group('commandes du tutoriel a police agrandie', () {
    Future<TutorialController> poser(
      WidgetTester tester, {
      required double largeur,
      required double police,
    }) async {
      tester.view.physicalSize = Size(largeur, 874);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final c = TutorialController(targets: TutorialTargets(
        modeSwitch: GlobalKey(), sos: GlobalKey(), recording: GlobalKey(),
        actions: GlobalKey(), layers: GlobalKey(),
      ));
      await c.startIfNeeded();
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(police)),
          child: Stack(children: [TutorialOverlay(controller: c)]),
        )),
      ));
      return c;
    }

    testWidgets('rien ne deborde de la carte', (tester) async {
      await poser(tester, largeur: 402, police: 2.0);
      expect(tester.takeException(), isNull);
    });

    // Les commandes sont hors de la zone defilante : elles doivent tenir a
    // l ecran sans qu on ait a deviner qu il faut faire defiler la carte.
    testWidgets('les commandes restent a l ecran', (tester) async {
      await poser(tester, largeur: 402, police: 2.0);

      final suivant = tester.getRect(find.byKey(const Key('tuto-suivant')));
      expect(suivant.bottom, lessThanOrEqualTo(874));
      expect(suivant.top, greaterThanOrEqualTo(0));
    });

    testWidgets('le bouton suivant reste touchable', (tester) async {
      await poser(tester, largeur: 402, police: 2.0);

      await tester.tap(find.byKey(const Key('tuto-suivant')));
      await tester.pump();

      expect(find.text('ÉTAPE 2 / 6'), findsOneWidget);
    });

    // L ordre de lecture tient, quelle que soit la mise en page retenue :
    // quitter d abord, avancer en dernier. La police de test etant bien plus
    // large que la vraie, on ne peut pas y affirmer « tout sur une ligne » —
    // c est verifie a l ecran.
    testWidgets('quitter reste a gauche, avancer a droite', (tester) async {
      await poser(tester, largeur: 402, police: 1.0);

      final passer = tester.getRect(find.byKey(const Key('tuto-passer')));
      final suivant = tester.getRect(find.byKey(const Key('tuto-suivant')));

      expect(passer.left, lessThanOrEqualTo(suivant.left));
      expect(passer.top, lessThanOrEqualTo(suivant.top));
    });

    // « Passer » a gauche, « Suivant » au bord droit de la carte : sans
    // largeur imposee le Wrap se retrecit sur son contenu et les deux se
    // collent a gauche.
    testWidgets('suivant est cale au bord droit de la carte', (tester) async {
      await poser(tester, largeur: 402, police: 1.0);

      final suivant = tester.getRect(find.byKey(const Key('tuto-suivant')));
      // Carte : 12 de marge dans la pile, 20 de padding interne.
      expect(suivant.right, closeTo(402 - 12 - 20, 1));
    });

    testWidgets('et sur un ecran etroit aussi', (tester) async {
      await poser(tester, largeur: 320, police: 1.5);

      await tester.tap(find.byKey(const Key('tuto-suivant')));
      await tester.pump();

      expect(find.text('ÉTAPE 2 / 6'), findsOneWidget);
    });
  });
}
