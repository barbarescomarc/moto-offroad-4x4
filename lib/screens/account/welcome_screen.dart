import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Porte d'entrée du compte rider : aucune saisie ici, seulement les deux
/// chemins possibles — créer un compte ou se connecter à un compte
/// existant. C'est l'écran que voit tout rider sans session valide (voir
/// `accountRedirect`).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('ecran-bienvenue'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.motorcycle, size: 72),
              const SizedBox(height: 16),
              const Text(
                'Moto Offroad 4x4',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Un compte rider est nécessaire pour accéder à la carte et à '
                'tes sorties.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                key: const Key('bouton-aller-inscription'),
                onPressed: () => context.go('/inscription'),
                child: const Text('Créer un compte'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('bouton-aller-connexion'),
                onPressed: () => context.go('/connexion'),
                child: const Text('J\'ai déjà un compte'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
