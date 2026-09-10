import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/account_provider.dart';
import '../../services/legal_documents.dart';

/// Mur bloquant entre le compte vérifié et le reste de l'application (voir
/// `accountRedirect` dans `account_gate.dart`) : la charte informe des
/// limites de la détection de chute et de la chaîne d'alerte, elle doit
/// être vue par tout rider, y compris ceux déjà inscrits, avant la carte.
///
/// Aucune sortie sans accepter — pas de « plus tard », pas de bouton
/// retour : un rider qui refuse ferme l'application.
class CharteScreen extends StatefulWidget {
  const CharteScreen({super.key});

  @override
  State<CharteScreen> createState() => _CharteScreenState();
}

class _CharteScreenState extends State<CharteScreen> {
  bool _coche = false;
  bool _enCours = false;
  String? _erreur;

  // Chargée une seule fois en mémoire : appeler LegalDocuments.charte()
  // directement dans build() recréerait un nouveau Future à chaque
  // reconstruction (ex. AccountProvider qui notifie), et le FutureBuilder
  // qui l'attend repasserait alors en chargement à chaque fois — jusqu'à
  // tourner indéfiniment si une reconstruction se déclenche pendant que le
  // précédent chargement se termine.
  late final Future<String> _charte = LegalDocuments.charte();

  Future<void> _accepter() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final ok = await context.read<AccountProvider>().acceptCharte();
    if (!mounted) return;
    if (ok) return;
    // Un succès notifie AccountProvider : accountRedirect fait disparaître
    // cet écran de lui-même, sans navigation explicite à faire ici. Un
    // échec (réseau, serveur) laisse le rider sur l'écran, case toujours
    // cochée, pour qu'un nouvel essai n'exige pas de tout recommencer.
    setState(() {
      _enCours = false;
      _erreur = "Impossible d'enregistrer ton acceptation, réessaie.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Charte du pilote'), automaticallyImplyLeading: false),
        body: Column(
          children: [
            Expanded(child: _texte()),
            SafeArea(top: false, child: _piedDePage()),
          ],
        ),
      ),
    );
  }

  Widget _texte() => FutureBuilder<String>(
        future: _charte,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(snap.data!),
          );
        },
      );

  Widget _piedDePage() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _coche,
                  onChanged: _enCours ? null : (v) => setState(() => _coche = v ?? false),
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text("J'ai lu et j'accepte la charte du pilote"),
                  ),
                ),
              ],
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: (_coche && !_enCours) ? _accepter : null,
              child: _enCours
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text("J'accepte"),
            ),
          ],
        ),
      );
}
