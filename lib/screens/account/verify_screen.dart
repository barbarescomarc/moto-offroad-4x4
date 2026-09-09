import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/account_provider.dart';
import '../../services/account_api_client.dart';
import 'account_error_messages.dart';

/// Attente de la vérification de l'adresse e-mail, entre l'inscription et
/// l'accès à la carte.
///
/// Trois issues, toutes nécessaires :
/// - *J'ai confirmé* : le rider revient de sa boîte mail et redemande une
///   vérification immédiate ;
/// - *Renvoyer l'e-mail* : le lien précédent a expiré ou n'est jamais
///   arrivé ;
/// - *Corriger mon adresse* : sans elle, une simple faute de frappe à
///   l'inscription enfermerait le rider dehors pour toujours, aucun e-mail
///   ne pouvant jamais lui parvenir.
///
/// L'écran interroge aussi le serveur toutes les 5 secondes en arrière-plan,
/// pour le rider qui confirme depuis un ordinateur pendant qu'il regarde
/// son téléphone : il n'a rien de plus à toucher.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  Timer? _sondage;
  String? _erreur;
  String? _info;
  bool _enCours = false;
  bool _correctionOuverte = false;
  final _nouvelleAdresse = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sondage = Timer.periodic(const Duration(seconds: 5), (_) async {
      final ok = await context.read<AccountProvider>().refreshVerification();
      if (ok && mounted) context.go('/');
    });
  }

  @override
  void dispose() {
    // Sans cette annulation, le Timer continuerait d'interroger le serveur
    // après la destruction de l'écran — fuite de ressource et appel réseau
    // sur un widget qui n'existe plus.
    _sondage?.cancel();
    _nouvelleAdresse.dispose();
    super.dispose();
  }

  Future<void> _jaiConfirme() async {
    setState(() {
      _erreur = null;
      _enCours = true;
    });
    final compte = context.read<AccountProvider>();
    final ok = await compte.refreshVerification();
    if (!mounted) return;
    setState(() {
      _enCours = false;
      if (!ok) {
        // `refreshVerification` ne distingue pas toujours « pas encore
        // vérifié » d'une panne réseau (voir AccountProvider) : une erreur
        // fraîchement posée prime, sinon c'est une adresse simplement pas
        // encore confirmée.
        _erreur = compte.lastError != null
            ? messagePour(compte.lastError!)
            : 'Ton adresse n\'est pas encore confirmée. As-tu ouvert le lien reçu par e-mail ?';
      }
    });
    if (ok) context.go('/');
  }

  Future<void> _renvoyer() async {
    setState(() {
      _erreur = null;
      _enCours = true;
    });
    final ok = await context.read<AccountProvider>().resendVerification();
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _info = ok ? 'E-mail renvoyé.' : null;
      _erreur = ok ? null : messagePour(AccountError.reseau);
    });
  }

  Future<void> _validerCorrection() async {
    final compte = context.read<AccountProvider>();
    final ok = await compte.changeEmail(_nouvelleAdresse.text.trim());
    if (!mounted) return;
    setState(() {
      if (ok) {
        _correctionOuverte = false;
        _erreur = null;
        _info = 'Adresse mise à jour. Vérifie ta nouvelle boîte mail.';
      } else {
        _erreur = messagePour(compte.lastError ?? AccountError.inconnue);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final compte = context.watch<AccountProvider>();
    return Scaffold(
      key: const Key('ecran-verification'),
      appBar: AppBar(title: const Text('Vérifie ton adresse')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Un e-mail de confirmation a été envoyé à '
            '${compte.email ?? 'ton adresse'}. Ouvre le lien qu\'il contient '
            'pour accéder à la carte.',
          ),
          if (_info != null) ...[
            const SizedBox(height: 16),
            Text(_info!, style: const TextStyle(color: Colors.greenAccent)),
          ],
          if (_erreur != null) ...[
            const SizedBox(height: 16),
            Text(_erreur!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('bouton-jai-confirme'),
            onPressed: _enCours ? null : _jaiConfirme,
            child: const Text('J\'ai confirmé'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('bouton-renvoyer'),
            onPressed: _enCours ? null : _renvoyer,
            child: const Text('Renvoyer l\'e-mail'),
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('bouton-corriger-adresse'),
            onPressed: _enCours ? null : () => setState(() => _correctionOuverte = !_correctionOuverte),
            child: const Text('Corriger mon adresse'),
          ),
          if (_correctionOuverte) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('champ-nouvelle-adresse'),
              controller: _nouvelleAdresse,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Nouvelle adresse e-mail'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('bouton-valider-correction'),
              onPressed: _enCours ? null : _validerCorrection,
              child: const Text('Valider la nouvelle adresse'),
            ),
          ],
        ],
      ),
    );
  }
}
