import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/widgets/account_banner.dart';

void main() {
  Widget enveloppe(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('affiche le message et le libelle de l action', (tester) async {
    await tester.pumpWidget(enveloppe(AccountBanner(
      icon: Icons.lock_clock,
      message: 'Ta session a expiré.',
      actionLabel: 'Se reconnecter',
      onAction: () {},
      onDismiss: () {},
    )));

    expect(find.text('Ta session a expiré.'), findsOneWidget);
    expect(find.text('Se reconnecter'), findsOneWidget);
  });

  testWidgets('le bouton d action declenche onAction', (tester) async {
    var appele = false;
    await tester.pumpWidget(enveloppe(AccountBanner(
      icon: Icons.lock_clock,
      message: 'msg',
      actionLabel: 'Agir',
      onAction: () => appele = true,
      onDismiss: () {},
    )));

    await tester.tap(find.text('Agir'));
    expect(appele, isTrue);
  });

  testWidgets('la fermeture declenche onDismiss', (tester) async {
    var ferme = false;
    await tester.pumpWidget(enveloppe(AccountBanner(
      icon: Icons.lock_clock,
      message: 'msg',
      actionLabel: 'Agir',
      onAction: () {},
      onDismiss: () => ferme = true,
    )));

    await tester.tap(find.byIcon(Icons.close));
    expect(ferme, isTrue);
  });

  test('formatGraceDeadline rend un format jour/mois/annee sans ambiguite', () {
    expect(formatGraceDeadline(DateTime(2026, 10, 8)), '08/10/2026');
  });
}
