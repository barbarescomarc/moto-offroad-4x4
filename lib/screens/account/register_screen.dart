import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/account_provider.dart';
import '../../services/account_api_client.dart';
import '../../services/legal_documents.dart';
import '../legal/legal_document_screen.dart';
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

  // Critique 1 de la revue finale : avant ce correctif, l'inscription
  // envoyait systématiquement `LegalDocuments.charteVersion`, sans jamais
  // montrer la charte — un rider se voyait donc enregistrer une acceptation
  // d'un document qu'il n'avait jamais vu, alors que c'est justement ce
  // texte qui l'avertit que la détection de chute peut échouer et que rien
  // ici ne remplace le 112. La case doit être cochée pour que le bouton
  // s'active, donc pour que la version soit envoyée — jamais au nom d'un
  // rider qui n'a pas coché.
  bool _accepteCharte = false;

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
      // Le bouton est désactivé tant que _accepteCharte est faux (voir
      // build()) : en pratique la version est donc toujours envoyée ici.
      // Explicite plutôt que la constante directe : jamais au nom d'un
      // rider qui n'a pas coché — voir accountRedirect dans
      // account_gate.dart pour ce que cet envoi évite ensuite (CharteScreen).
      charteVersion: _accepteCharte ? LegalDocuments.charteVersion : null,
    );
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _erreur = ok ? null : messagePour(compte.lastError ?? AccountError.inconnue);
    });
    if (ok) context.go('/verification');
  }

  Future<void> _ouvrirCharte() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const LegalDocumentScreen(title: 'Charte du pilote', loader: LegalDocuments.charte),
    ));
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
          const SizedBox(height: 16),
          _accepterCharte(),
          if (_erreur != null) ...[
            const SizedBox(height: 16),
            Text(_erreur!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('bouton-inscription'),
            onPressed: (_enCours || !_accepteCharte) ? null : _valider,
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

  // Même forme que _conditions() dans publish_trace_screen.dart : case à
  // cocher plus lien vers le texte complet, dans un Wrap pour que le lien
  // souligné reste sur la même ligne que le texte qui le précède.
  Widget _accepterCharte() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          key: const Key('case-acceptation-charte'),
          value: _accepteCharte,
          onChanged: _enCours ? null : (v) => setState(() => _accepteCharte = v ?? false),
        ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text("J'ai lu et j'accepte la "),
              GestureDetector(
                onTap: _ouvrirCharte,
                child: const Text(
                  'charte du pilote',
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
