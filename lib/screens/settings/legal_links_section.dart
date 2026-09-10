import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../services/legal_documents.dart';
import '../legal/legal_document_screen.dart';

/// Section « Textes légaux » de l'écran Réglages (Trouvaille I3 de la revue
/// finale) : avant ce correctif, rien dans Réglages ne renvoyait vers la
/// charte du pilote ni vers les conditions de publication — un rider les
/// acceptait une fois (inscription, première publication) sans plus jamais
/// pouvoir les relire ensuite.
///
/// Widget à part entière (pas une simple méthode privée de SettingsScreen) :
/// il ne dépend que de la navigation, ce qui permet de le tester sans monter
/// tout SettingsScreen — dont une autre section (MapCacheTile) exige un
/// backend FMTC/ObjectBox initialisé, hors de portée d'un test widget pur.
class LegalLinksSection extends StatelessWidget {
  const LegalLinksSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('TEXTES LÉGAUX', style: TextStyle(
          fontFamily: 'Rajdhani', fontSize: 12, color: AppColors.textMuted, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        ListTile(
          key: const Key('entree-charte-du-pilote'),
          leading: const Icon(Icons.shield_outlined, color: AppColors.textMuted),
          title: const Text('Charte du pilote', style: TextStyle(color: Colors.white)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
          contentPadding: EdgeInsets.zero,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const LegalDocumentScreen(title: 'Charte du pilote', loader: LegalDocuments.charte),
          )),
        ),
        ListTile(
          key: const Key('entree-conditions-publication'),
          leading: const Icon(Icons.description_outlined, color: AppColors.textMuted),
          title: const Text('Conditions de publication', style: TextStyle(color: Colors.white)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
          contentPadding: EdgeInsets.zero,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const LegalDocumentScreen(
              title: 'Conditions de publication',
              loader: LegalDocuments.conditionsPublication,
            ),
          )),
        ),
      ],
    );
  }
}
