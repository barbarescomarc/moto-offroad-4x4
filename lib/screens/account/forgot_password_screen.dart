import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/account_provider.dart';
import '../../services/account_api_client.dart';
import 'account_error_messages.dart';

/// Réinitialisation de mot de passe.
///
/// Le serveur répond systématiquement de la même façon à `POST
/// /password/forgot`, que l'adresse existe ou non (anti-énumération : voir
/// `AccountApiClient.forgotPassword`). Cet écran doit donc toujours afficher
/// le même message de confirmation — annoncer « adresse inconnue » ici
/// révélerait exactement ce que le serveur refuse de révéler.
///
/// La seule exception honnête est un échec qui n'a rien à voir avec
/// l'existence du compte (panne réseau, trop de tentatives...) : l'annoncer
/// ne révèle rien sur l'adresse, et le taire laisserait le rider croire à
/// tort qu'un e-mail est en route.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  String? _message;
  bool _enCours = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _message = null;
      _enCours = true;
    });

    final compte = context.read<AccountProvider>();
    final ok = await compte.forgotPassword(_email.text.trim());
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _message = ok
          ? 'Si un compte existe pour cette adresse, le lien vient de partir.'
          : messagePour(compte.lastError ?? AccountError.inconnue);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('ecran-mot-de-passe-oublie'),
      appBar: AppBar(title: const Text('Mot de passe oublié')),
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
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('bouton-reinitialiser'),
            onPressed: _enCours ? null : _valider,
            child: Text(_enCours ? 'Envoi…' : 'Recevoir un lien'),
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('bouton-vers-connexion'),
            onPressed: _enCours ? null : () => context.go('/connexion'),
            child: const Text('Retour à la connexion'),
          ),
        ],
      ),
    );
  }
}
