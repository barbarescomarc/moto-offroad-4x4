import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/screens/legal/legal_document_screen.dart';
import 'package:moto_offroad/screens/settings/legal_links_section.dart';

// LegalLinksSection seule, pas SettingsScreen au complet : ce dernier monte
// aussi MapCacheTile, qui exige un backend FMTC/ObjectBox initialisé (voir
// MapTileCache.initialize() dans main.dart) — hors de portée d'un test
// widget pur, comme MapScreen ailleurs dans ce dépôt (voir
// test/app/router_test.dart). La section a justement été extraite en widget
// à part pour rester testable indépendamment de ce voisin encombrant.
Widget ecranDeTest() => const MaterialApp(
      home: Scaffold(body: LegalLinksSection()),
    );

void main() {
  // Trouvaille I3 de la revue finale : rien dans Réglages ne renvoyait vers
  // la charte du pilote ni vers les conditions de publication — un rider
  // les acceptait une fois (inscription, première publication) sans plus
  // jamais pouvoir les relire ensuite.

  testWidgets("l entree Charte du pilote ouvre le texte complet", (tester) async {
    await tester.runAsync(() async {
      // LegalDocumentScreen lit docs/legal/charte-du-pilote.md via
      // rootBundle : une vraie lecture de fichier, hors de l'horloge
      // simulée (même remarque que pour CharteScreen, voir
      // account_screens_test.dart et charte_screen_test.dart).
      await tester.pumpWidget(ecranDeTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('entree-charte-du-pilote')));
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      // Le 112 : preuve que le vrai texte est chargé, pas un texte de test.
      await tester.dragUntilVisible(
        find.textContaining('112'),
        find.byType(Scrollable),
        const Offset(0, -80),
      );
      expect(find.textContaining('112'), findsWidgets);
    });
  });

  testWidgets("l entree Conditions de publication ouvre le texte complet", (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(ecranDeTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('entree-conditions-publication')));
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(find.text('Conditions de publication'), findsWidgets);
      await tester.dragUntilVisible(
        find.textContaining("droits d'exploitation"),
        find.byType(Scrollable),
        const Offset(0, -80),
      );
      expect(find.textContaining("droits d'exploitation"), findsWidgets);
    });
  });
}
