import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/screens/info/info_screen.dart';

void main() {
  // Regression du 2026-09-13 : la section INFO des Reglages s ouvrait sur du
  // vide — plus de reglementation offroad ni de regles du bivouac.
  //
  // `embedded: true` veut dire « je suis posee dans la zone defilante de
  // quelqu un d autre ». Reproduit ici le montage exact de SettingsScreen :
  // SingleChildScrollView > Column > ExpansionTile > InfoScreen(embedded).
  // La hauteur y est non bornee ; une liste defilante ne peut pas s y poser.
  testWidgets('depliee dans les Reglages, la section INFO montre la loi',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                ExpansionTile(
                  title: Text('INFO'),
                  children: [InfoScreen(embedded: true)],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('INFO'));
    await tester.pumpAndSettle();

    expect(find.text('OFFROAD — RÉGLEMENTATION FRANCE'), findsOneWidget);
    expect(find.text('BIVOUAC SAUVAGE — CE QUE DIT LA LOI'), findsOneWidget);
  });

  // L'ecran autonome, lui, est bien la zone defilante : il doit le rester.
  testWidgets('en plein ecran, la page INFO defile d elle meme', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: InfoScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('BIVOUAC SAUVAGE — CE QUE DIT LA LOI'), findsOneWidget);
  });

  // Repliee, la carte est bien plus etroite qu en plein ecran : le libelle
  // des numeros d urgence debordait par la droite (32 px, constate a l ecran
  // le 2026-09-13) au lieu de passer a la ligne.
  testWidgets('a l etroit, rien ne deborde', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 280,
              child: InfoScreen(embedded: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('SAMU — urgences médicales'), findsOneWidget);
  });
}
