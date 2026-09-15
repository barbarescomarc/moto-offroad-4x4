import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Une action d'une famille, telle que la feuille la présente.
class ActionFamille {
  const ActionFamille({
    required this.icone,
    required this.nom,
    required this.description,
    required this.onChoisi,
    this.couleur = AppColors.accent,
  });

  final IconData icone;
  final String nom;
  final String description;
  final VoidCallback onChoisi;
  final Color couleur;
}

/// La feuille d'une famille de commandes — Communauté, Guidage.
///
/// Elle existe pour que le cadran reste facultatif. L'appui long est un
/// raccourci pour qui le connaît ; l'appui court doit suffire à tout faire,
/// avec les noms écrits en toutes lettres. Sans elle, une commande repliée
/// derrière un geste que personne n'a enseigné est une commande perdue.
class FeuilleFamille extends StatelessWidget {
  const FeuilleFamille({
    super.key,
    required this.titre,
    required this.actions,
  });

  final String titre;
  final List<ActionFamille> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 16),
            Text(titre.toUpperCase(), style: const TextStyle(
              fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700,
              color: AppColors.accent, letterSpacing: 1,
            )),
            const SizedBox(height: 4),
            const Text(
              'Appui long sur le bouton pour les atteindre sans passer par ici.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            ...actions.map((a) => ListTile(
                  key: Key('famille-${a.nom}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: a.couleur.withValues(alpha: .12),
                    ),
                    child: Icon(a.icone, color: a.couleur, size: 21),
                  ),
                  title: Text(a.nom, style: const TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.foreground)),
                  subtitle: Text(a.description, style: const TextStyle(
                    fontSize: 12, color: AppColors.mutedForeground)),
                  onTap: () {
                    Navigator.of(context).pop();
                    a.onChoisi();
                  },
                )),
          ],
        ),
      ),
    );
  }
}
