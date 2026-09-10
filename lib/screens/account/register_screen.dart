import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/account_provider.dart';
import '../../services/account_api_client.dart';
import '../../services/legal_documents.dart';
import 'account_error_messages.dart';

/// Création de compte : c'est le passage obligé avant tout accès à la
/// carte pour un rider sans session. Le mot de passe est vérifié
/// localement avant tout appel réseau — voir [kMinPasswordLength].
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _email = TextEditingController();
  final _motDePasse = TextEditingController();
  final _prenom = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _email.dispose();
    _motDePasse.dispose();
    _prenom.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_motDePasse.text.length < kMinPasswordLength) {
      setState(() => _erreur = messagePour(AccountError.motDePasseTropCourt));
      return;
    }
    setState(() {
      _erreur = null;
      _enCours = true;
    });

    final compte = context.read<AccountProvider>();
    final ok = await compte.register(
      email: _email.text.trim(),
      password: _motDePasse.text,
      displayName: _prenom.text.trim(),
      // Un compte créé depuis cette version n'a donc jamais à repasser par
      // CharteScreen — voir accountRedirect dans account_gate.dart.
      charteVersion: LegalDocuments.charteVersion,
    );
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _erreur = ok ? null : messagePour(compte.lastError ?? AccountError.inconnue);
    });
    if (ok) context.go('/verification');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('ecran-inscription'),
      appBar: AppBar(title: const Text('Créer un compte')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            key: const Key('champ-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Adresse e-mail'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('champ-mot-de-passe'),
            controller: _motDePasse,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Mot de passe (au moins $kMinPasswordLength signes)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('champ-prenom'),
            controller: _prenom,
            decoration: const InputDecoration(labelText: 'Prénom (facultatif)'),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 16),
            Text(_erreur!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('bouton-inscription'),
            onPressed: _enCours ? null : _valider,
            child: Text(_enCours ? 'Création…' : 'Créer mon compte'),
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('bouton-vers-connexion'),
            onPressed: _enCours ? null : () => context.go('/connexion'),
            child: const Text('J\'ai déjà un compte'),
          ),
        ],
      ),
    );
  }
}
