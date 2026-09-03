import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';
import '../services/update_checker.dart';

/// Section « Application » des réglages : version installée, partage du lien
/// de téléchargement, vérification manuelle des mises à jour.
///
/// L'application est distribuée hors magasin. Personne ne prévient
/// l'utilisateur qu'une version existe, et rien ne l'installe à sa place : le
/// lien direct est donc autant l'outil de diffusion que celui de mise à jour.
class UpdateTile extends StatefulWidget {
  const UpdateTile({super.key});

  @override
  State<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<UpdateTile> {
  String _version = '…';
  bool _verificationEnCours = false;

  @override
  void initState() {
    super.initState();
    _lireVersion();
  }

  Future<void> _lireVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  Future<void> _verifier() async {
    setState(() => _verificationEnCours = true);
    final maj = await UpdateChecker.checkIfDue(
      currentVersion: _version,
      force: true,
    );
    if (!mounted) return;
    setState(() => _verificationEnCours = false);

    if (maj == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucune mise à jour disponible.'),
      ));
      return;
    }
    await afficherMiseAJour(context, maj);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.smartphone),
          title: const Text('Version installée'),
          subtitle: Text(_version),
        ),
        ListTile(
          leading: const Icon(Icons.ios_share),
          title: const Text('Partager l\'application'),
          subtitle: const Text('Envoie un lien de téléchargement direct. '
              'Le destinataire devra autoriser l\'installation depuis '
              'cette source.'),
          onTap: () => Share.share(
            'MOTO OFFROAD 4X4 — GPS pour la moto et le 4x4 tout-terrain.\n'
            'Télécharger : ${UpdateChecker.downloadUrl}',
          ),
        ),
        ListTile(
          leading: _verificationEnCours
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update),
          title: const Text('Vérifier les mises à jour'),
          onTap: _verificationEnCours ? null : _verifier,
        ),
      ],
    );
  }
}

/// Propose le téléchargement d'une version plus récente.
///
/// Volontairement une boîte de dialogue et non une installation automatique :
/// hors magasin, télécharger un APK est une décision que l'utilisateur prend.
Future<void> afficherMiseAJour(BuildContext context, UpdateInfo maj) async {
  final telecharger = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Version ${maj.version} disponible'),
      content: const Text(
          'Une nouvelle version de l\'application est publiée.\n\n'
          'Le téléchargement s\'ouvre dans le navigateur. Installez le '
          'fichier par-dessus l\'application actuelle : vos sorties '
          'enregistrées sont conservées.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Télécharger'),
        ),
      ],
    ),
  );
  if (telecharger != true) return;
  await launchUrl(Uri.parse(maj.url), mode: LaunchMode.externalApplication);
}

/// Bandeau discret affiché au démarrage quand une version plus récente existe.
class UpdateBanner extends StatelessWidget {
  final UpdateInfo maj;
  final VoidCallback onDismiss;
  const UpdateBanner({super.key, required this.maj, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgPanel,
      child: ListTile(
        leading: const Icon(Icons.system_update, color: AppColors.orange),
        title: Text('Version ${maj.version} disponible',
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => afficherMiseAJour(context, maj),
              child: const Text('Voir'),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.white),
              onPressed: onDismiss,
              tooltip: 'Masquer',
            ),
          ],
        ),
      ),
    );
  }
}
