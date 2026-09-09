import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/router.dart';
import '../../providers/account_provider.dart';
import '../../services/account_api_client.dart';
import '../../services/tutorial_controller.dart';
import 'account_error_messages.dart';

/// Écran « Mon compte » : identité du rider connecté, et les trois actions
/// qui ne trouvent leur place nulle part ailleurs.
///
/// La suppression est exigée par le RGPD et par les règles de l'App Store —
/// et surtout, elle est irréversible : le serveur efface réellement les
/// données. Elle ne part donc jamais sans une confirmation explicite du
/// rider, voir [_supprimerCompte].
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _enCours = false;
  String? _erreur;

  Future<void> _seDeconnecter() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    await context.read<AccountProvider>().logout();
    // Pas de navigation explicite : le changement de statut fait réagir le
    // `redirect` du routeur (voir `account_gate.dart`), qui ramène seul le
    // rider vers l'écran de bienvenue.
    if (mounted) setState(() => _enCours = false);
  }

  Future<void> _supprimerCompte() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer mon compte ?'),
        content: const Text(
          'Cette opération est définitive : ton compte et toutes tes '
          'données seront effacés du serveur, sans possibilité de retour '
          'en arrière.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: const Key('bouton-confirmer-suppression'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oui, supprimer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final compte = context.read<AccountProvider>();
    final ok = await compte.deleteAccount();
    if (!mounted) return;
    setState(() {
      _enCours = false;
      // Un succès ramène déjà le rider vers l'écran de bienvenue via le
      // routeur (statut `deconnecte`) : rien à afficher ici dans ce cas.
      if (!ok) _erreur = messagePour(compte.lastError ?? AccountError.inconnue);
    });
  }

  Future<void> _revoirLeTutoriel() async {
    await TutorialController.forgetCompletion();
    if (mounted) context.go(AppRoutes.map);
  }

  @override
  Widget build(BuildContext context) {
    final compte = context.watch<AccountProvider>();
    return Scaffold(
      key: const Key('ecran-mon-compte'),
      appBar: AppBar(title: const Text('Mon compte')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            compte.displayName ?? 'Rider',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(compte.email ?? '',
              style: const TextStyle(color: Colors.white70)),
          if (_erreur != null) ...[
            const SizedBox(height: 16),
            Text(_erreur!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 32),
          OutlinedButton(
            key: const Key('bouton-revoir-tutoriel'),
            onPressed: _enCours ? null : _revoirLeTutoriel,
            child: const Text('Revoir le tutoriel'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('bouton-deconnexion'),
            onPressed: _enCours ? null : _seDeconnecter,
            child: const Text('Se déconnecter'),
          ),
          const SizedBox(height: 24),
          TextButton(
            key: const Key('bouton-supprimer-compte'),
            onPressed: _enCours ? null : _supprimerCompte,
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Supprimer mon compte'),
          ),
        ],
      ),
    );
  }
}
