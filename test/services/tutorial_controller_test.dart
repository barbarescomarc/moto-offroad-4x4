import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/services/tutorial_controller.dart';
import 'package:moto_offroad/services/tutorial_steps.dart';

TutorialTargets cibles() => TutorialTargets(
      modeSwitch: GlobalKey(), sos: GlobalKey(), recording: GlobalKey(),
      actions: GlobalKey(), layers: GlobalKey(),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('le tutoriel compte six etapes', () {
    expect(buildTutorialSteps(cibles()).length, 6);
  });

  test('la premiere etape n a pas de cible', () {
    expect(buildTutorialSteps(cibles()).first.target, isNull);
  });

  test('il se declenche la premiere fois et pas la seconde', () async {
    final premier = TutorialController(targets: cibles());
    await premier.startIfNeeded();
    expect(premier.visible, isTrue);
    await premier.skip();
    expect(premier.visible, isFalse);

    final second = TutorialController(targets: cibles());
    await second.startIfNeeded();
    expect(second.visible, isFalse, reason: 'un tutoriel deja vu ne revient pas');
  });

  test('la navigation avance, recule et se termine', () async {
    final c = TutorialController(targets: cibles());
    await c.startIfNeeded();
    expect(c.index, 0);
    c.next();
    expect(c.index, 1);
    c.previous();
    expect(c.index, 0);
    for (var i = 0; i < 10; i++) {
      c.next();
    }
    expect(c.visible, isFalse, reason: 'passe la derniere etape le tutoriel se ferme');
  });

  test('il est rejouable depuis les reglages', () async {
    final c = TutorialController(targets: cibles());
    await c.startIfNeeded();
    await c.skip();
    await c.replay();
    expect(c.visible, isTrue);
    expect(c.index, 0);
  });

  test('disposer pendant que startIfNeeded attend shared_preferences ne leve pas', () async {
    // initState ne peut pas attendre startIfNeeded : l ecran peut donc
    // etre demonte (et le controleur libere) avant que
    // SharedPreferences.getInstance() n ait rendu la main. Sans garde,
    // le notifyListeners qui suit leverait sur un ChangeNotifier disposé.
    final c = TutorialController(targets: cibles());
    final demarrage = c.startIfNeeded();
    c.dispose();
    await demarrage;
  });
}
