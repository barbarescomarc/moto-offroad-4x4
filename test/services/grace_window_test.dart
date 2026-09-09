import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/services/grace_window.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('une installation neuve n a aucun delai', () async {
    final g = GraceWindow();
    await g.evaluate(hasLegacyData: false);
    expect(g.active, isFalse);
    expect(g.deadline, isNull);
  });

  test('une installation anterieure recoit trente jours', () async {
    final depart = DateTime(2026, 9, 8);
    final g = GraceWindow();
    await g.evaluate(hasLegacyData: true, now: depart);
    expect(g.active, isTrue);
    expect(g.deadline, DateTime(2026, 10, 8));
  });

  test('l echeance est conservee entre deux lancements', () async {
    final depart = DateTime(2026, 9, 8);
    await GraceWindow().evaluate(hasLegacyData: true, now: depart);

    final second = GraceWindow();
    await second.evaluate(hasLegacyData: true, now: depart.add(const Duration(days: 5)));
    expect(second.deadline, DateTime(2026, 10, 8), reason: 'l echeance ne se repousse pas a chaque lancement');
    expect(second.active, isTrue);
  });

  test('passe l echeance le delai est clos', () async {
    final depart = DateTime(2026, 9, 8);
    await GraceWindow().evaluate(hasLegacyData: true, now: depart);

    final apres = GraceWindow();
    await apres.evaluate(hasLegacyData: true, now: depart.add(const Duration(days: 31)));
    expect(apres.active, isFalse);
  });

  test('une installation neuve ne recoit pas de delai meme si le telephone en a deja eu un', () async {
    SharedPreferences.setMockInitialValues({});
    final g = GraceWindow();
    await g.evaluate(hasLegacyData: false, now: DateTime(2026, 9, 8));
    expect(g.active, isFalse);
  });
}
