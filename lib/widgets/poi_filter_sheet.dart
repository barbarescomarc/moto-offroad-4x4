import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../models/poi.dart';
import '../providers/fuel_poi_provider.dart';

/// Choisir ce qui reste sur la carte.
///
/// Une recherche de camping-car remonte six familles de points d'un coup —
/// stations, aires, vidanges, points d'eau, bornes, garages. Sur une carte de
/// ville, chaque fontaine publique est un point d'eau : la carte devient
/// illisible et cache ce qu'on cherchait vraiment.
///
/// Ne propose que les catégories réellement trouvées : offrir de filtrer une
/// famille absente des résultats laisse croire qu'on a raté quelque chose.
class PoiFilterSheet extends StatelessWidget {
  const PoiFilterSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final poi = context.watch<FuelPoiProvider>();
    final categories = poi.categoriesTrouvees;

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
                color: const Color(0xFF2A2A3E),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 16),
            const Text('AFFICHER SUR LA CARTE', style: TextStyle(
              fontFamily: 'Rajdhani', fontSize: 16, fontWeight: FontWeight.w700,
              color: AppColors.orange, letterSpacing: 1,
            )),
            const SizedBox(height: 4),
            Text(
              categories.isEmpty
                  ? 'Lance une recherche pour avoir quelque chose à filtrer.'
                  : 'Décoche ce que tu ne veux pas voir. Le choix est gardé.',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),

            if (categories.isNotEmpty) ...[
              Wrap(
                spacing: 8, runSpacing: 8,
                children: categories.map((c) => _puce(context, poi, c)).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('filtre-tout-afficher'),
                      onPressed: poi.toutAfficher,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF2A2A3E)),
                        minimumSize: const Size(0, 44),
                      ),
                      child: const Text('Tout afficher'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      child: const Text('Terminé'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Le nombre trouvé accompagne le libellé : « Point d'eau 47 » explique à
  /// lui seul pourquoi la carte était encombrée.
  Widget _puce(BuildContext context, FuelPoiProvider poi, PoiCategory categorie) {
    final affichee = poi.estAffichee(categorie);
    return FilterChip(
      key: Key('filtre-${categorie.name}'),
      label: Text('${categorie.emoji} ${categorie.label}  ${poi.compte(categorie)}'),
      selected: affichee,
      onSelected: (_) => poi.basculerCategorie(categorie),
      labelStyle: TextStyle(
        color: affichee ? Colors.white : Colors.white54,
        fontSize: 13,
      ),
      selectedColor: Color(categorie.colorValue),
      backgroundColor: AppColors.bgPanel,
      checkmarkColor: Colors.white,
      showCheckmark: true,
    );
  }
}
