import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/account_provider.dart';
import '../../services/account_api_client.dart';
import 'account_error_messages.dart';

/// Connexion à un compte déjà existant.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _motDePasse = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _email.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _erreur = null;
      _enCours = true;
    });

    final compte = context.read<AccountProvider>();
    final ok = await compte.login(email: _email.text.trim(), password: _motDePasse.text);
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _erreur = ok ? null : messagePour(compte.lastError ?? AccountError.inconnue);
    });
    // Pas de navigation explicite en cas de succès : le rider peut être
    // connecté mais pas encore vérifié — c'est le `redirect` du routeur qui
    // décide de la destination selon le statut réel.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('ecran-connexion'),
      appBar: AppBar(title: const Text('Se connecter')),
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
            decoration: const InputDecoration(labelText: 'Mot de passe'),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 16),
            Text(_erreur!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('bouton-connexion'),
            onPressed: _enCours ? null : _valider,
            child: Text(_enCours ? 'Connexion…' : 'Se connecter'),
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('bouton-mot-de-passe-oublie'),
            onPressed: _enCours ? null : () => context.go('/mot-de-passe-oublie'),
            child: const Text('Mot de passe oublié ?'),
          ),
          TextButton(
            key: const Key('bouton-vers-inscription'),
            onPressed: _enCours ? null : () => context.go('/inscription'),
            child: const Text('Créer un compte'),
          ),
        ],
      ),
    );
  }
}
