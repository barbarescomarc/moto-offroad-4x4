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
}
