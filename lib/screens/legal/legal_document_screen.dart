import 'package:flutter/material.dart';

/// Écran de lecture seule d'un texte légal embarqué (charte du pilote,
/// conditions de publication) : même forme partout où un rider a besoin de
/// le consulter — le lien depuis l'inscription (voir `RegisterScreen`) et
/// depuis la publication d'une trace (voir `PublishTraceScreen`), et les
/// entrées « Réglages » qui permettent de le relire après coup (voir
/// `SettingsScreen`). Une seule maison pour ce rendu, pour qu'un changement
/// (ex. passage au Markdown) n'ait jamais à être fait à trois endroits.
class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({super.key, required this.title, required this.loader});

  final String title;

  /// Charge le texte — typiquement une des méthodes de `LegalDocuments`.
  final Future<String> Function() loader;

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  // Chargé une seule fois en mémoire (pas dans build()) : appeler
  // widget.loader() directement dans build() recréerait un nouveau Future à
  // chaque reconstruction, et le FutureBuilder qui l'attend repasserait
  // alors en chargement à chaque fois (voir la même remarque, plus
  // détaillée, sur CharteScreen._charte). Champ mutable pour permettre un
  // nouvel essai si la ressource embarquée échoue à charger.
  late Future<String> _texte = widget.loader();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<String>(
        future: _texte,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Impossible de charger ce document.', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() => _texte = widget.loader()),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(snap.data!),
          );
        },
      ),
    );
  }
}
