import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app/theme.dart';

/// Bandeau non bloquant, sur le modèle d'`UpdateBanner`
/// (`widgets/update_tile.dart`) : un message, une action principale, une
/// fermeture pour la session en cours. Sert les deux besoins du lot comptes
/// riders — annoncer l'échéance du délai de grâce (voir `GraceWindow`) et
/// signaler qu'une session doit être renouvelée
/// (`AccountStatus.sessionARenouveler`) — voir `accountBannerKind` pour la
/// règle qui choisit lequel afficher. Ni l'un ni l'autre n'est un mur :
/// aucun des deux ne doit jamais fermer l'accès à l'application.
class AccountBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onDismiss;
  const AccountBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgPanel,
      child: ListTile(
        leading: Icon(icon, color: AppColors.orange),
        title: Text(message, style: const TextStyle(color: Colors.white, fontSize: 14)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel),
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

/// Formate l'échéance du délai de grâce pour le bandeau.
///
/// Format numérique (jour/mois/année) plutôt que le nom du mois en toutes
/// lettres : l'application n'initialise aucune donnée de locale `intl`
/// (`initializeDateFormatting`), et ce format n'en a pas besoin — il reste
/// d'ailleurs sans ambiguïté, contrairement à un format anglophone.
String formatGraceDeadline(DateTime deadline) => DateFormat('dd/MM/yyyy').format(deadline);
