import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../models/poi.dart';
import '../models/vehicle_kind.dart';
import '../providers/aires_provider.dart';
import '../providers/poi_provider.dart';
import '../providers/settings_provider.dart';

/// Où la recherche se fait. « Ici » n'apparaît que lorsque la carte a été
/// déplacée : tant qu'on regarde sa propre position, c'est la même chose
/// qu'autour de soi.
enum OuChercher { autourDeMoi, ici, destination, leLongDeLaRoute }

/// La feuille unique : ce qu'on veut voir autour, et où le chercher.
///
/// Elle remplace deux écrans qui posaient la même question à deux endroits —
/// la recherche touristique d'un côté, les stations et leurs filtres de
/// l'autre. Le pilote coche, la carte affiche ; d'où viennent les points ne
/// le regarde pas.
class FeuillePoi extends StatefulWidget {
  const FeuillePoi({
    super.key,
    required this.positionPilote,
    required this.centreCarte,
    this.destination,
    this.itineraire,
    this.onAires,
  });

  final LatLng? positionPilote;
  final LatLng centreCarte;
  final LatLng? destination;
  final List<LatLng>? itineraire;

  /// Les aires se chargent depuis la carte, qui seule connaît la zone
  /// regardée. La feuille ne fait que le demander.
  final Future<void> Function()? onAires;

  @override
  State<FeuillePoi> createState() => _FeuillePoiState();
}

class _FeuillePoiState extends State<FeuillePoi> {
  OuChercher _ou = OuChercher.autourDeMoi;

  /// Le déplacement à partir duquel « ici » cesse d'être « autour de moi ».
  static const double _loinMetres = 1000;

  bool get _carteDeplacee {
    final moi = widget.positionPilote;
    if (moi == null) return true;
    return const Distance().as(LengthUnit.Meter, moi, widget.centreCarte) > _loinMetres;
  }

  @override
  void initState() {
    super.initState();
    if (widget.positionPilote == null && _carteDeplacee) _ou = OuChercher.ici;
  }

  @override
  Widget build(BuildContext context) {
    final poi      = context.watch<PoiProvider>();
    final settings = context.watch<SettingsProvider>();
    final vehicule = settings.vehicleKind;

    // Ce que le véhicule peut vouloir, moins les aires : elles ont leur
    // propre chaîne et leur propre case, plus bas.
    final pratiques = vehicule.poiCategories
        .where((c) => c != PoiCategory.aireCampingCar)
        .toList();
    const aVoir = [
      PoiCategory.viewpoint,
      PoiCategory.naturalSite,
      PoiCategory.heritage,
      PoiCategory.guestHouse,
    ];

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
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
          const Text('AUTOUR DE MOI', style: TextStyle(
            fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700,
            color: AppColors.accent, letterSpacing: 1,
          )),
          const SizedBox(height: 16),

          _titre('OÙ CHERCHER'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _puceOu('Autour de moi', OuChercher.autourDeMoi,
                widget.positionPilote != null),
            if (_carteDeplacee) _puceOu('Ici', OuChercher.ici, true),
            _puceOu('À destination', OuChercher.destination, widget.destination != null),
            _puceOu('Le long de la route', OuChercher.leLongDeLaRoute,
                (widget.itineraire?.isNotEmpty ?? false)),
          ]),
          const SizedBox(height: 18),

          _titre('QUOI AFFICHER'),
          Wrap(spacing: 8, runSpacing: 8,
              children: pratiques.map((c) => _puceCategorie(poi, c)).toList()),

          if (vehicule.hasGabarit) ...[
            const SizedBox(height: 12),
            _titre('CAMPING-CAR'),
            _puceAires(),
          ],

          const SizedBox(height: 12),
          _titre('À VOIR'),
          Wrap(spacing: 8, runSpacing: 8,
              children: aVoir.map((c) => _puceCategorie(poi, c)).toList()),

          const SizedBox(height: 18),
          Row(children: [
            Text('Rayon : ${poi.rayonKm} km',
                style: const TextStyle(fontSize: 13, color: AppColors.mutedForeground)),
            Expanded(
              child: Slider(
                value: poi.rayonKm.toDouble(),
                min: 5, max: 50, divisions: 9,
                label: '${poi.rayonKm} km',
                onChanged: (v) => poi.setRayonKm(v.round()),
              ),
            ),
          ]),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('poi-afficher'),
              onPressed: (poi.selection.isEmpty || poi.enCours) ? null : _chercher,
              icon: poi.enCours
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.onPrimary))
                  : const Icon(Icons.search),
              label: Text(poi.enCours ? 'Recherche…' : 'Afficher'),
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            ),
          ),
          if (poi.indisponible) ...[
            const SizedBox(height: 10),
            const Row(children: [
              Icon(Icons.cloud_off, size: 16, color: AppColors.statusOrange),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Une des sources n\'a pas répondu. Ce qui s\'affiche peut être incomplet.',
                style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
              )),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _titre(String texte) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texte, style: const TextStyle(
          fontFamily: 'Inter', fontSize: 12,
          color: AppColors.textMuted, letterSpacing: 1,
        )),
      );

  Widget _puceOu(String libelle, OuChercher mode, bool possible) {
    final actif = _ou == mode;
    return ChoiceChip(
      label: Text(libelle),
      selected: actif,
      onSelected: possible ? (_) => setState(() => _ou = mode) : null,
      labelStyle: TextStyle(
        color: !possible
            ? AppColors.textMuted
            : (actif ? AppColors.foreground : AppColors.mutedForeground),
        fontSize: 13,
      ),
      selectedColor: AppColors.accent.withValues(alpha: .18),
      backgroundColor: AppColors.card,
      disabledColor: AppColors.card.withValues(alpha: .5),
    );
  }

  Widget _puceCategorie(PoiProvider poi, PoiCategory categorie) {
    final coche = poi.selection.contains(categorie);
    return FilterChip(
      key: Key('poi-${categorie.name}'),
      label: Text('${categorie.emoji} ${categorie.label}'),
      selected: coche,
      onSelected: (_) => poi.basculer(categorie),
      labelStyle: TextStyle(
        color: coche ? AppColors.foreground : AppColors.mutedForeground,
        fontSize: 13,
      ),
      selectedColor: Color(categorie.colorValue).withValues(alpha: .22),
      backgroundColor: AppColors.card,
      checkmarkColor: AppColors.accent,
    );
  }

  /// Les aires gardent leur chaîne : le serveur GO FREE les sert avec leur
  /// gabarit et les relevés des autres pilotes, ce qu'aucune des deux autres
  /// sources ne sait faire.
  Widget _puceAires() {
    final aires = context.watch<AiresProvider>();
    return FilterChip(
      key: const Key('poi-aires'),
      label: const Text('🚐 Aires de camping-car'),
      selected: aires.visible,
      onSelected: (_) => widget.onAires?.call(),
      labelStyle: TextStyle(
        color: aires.visible ? AppColors.foreground : AppColors.mutedForeground,
        fontSize: 13,
      ),
      selectedColor: AppColors.accent.withValues(alpha: .22),
      backgroundColor: AppColors.card,
      checkmarkColor: AppColors.accent,
    );
  }

  Future<void> _chercher() async {
    final poi = context.read<PoiProvider>();
    final vehicule = context.read<SettingsProvider>().vehicleKind;
    final navigateur = Navigator.of(context);

    switch (_ou) {
      case OuChercher.autourDeMoi:
        await poi.chercher(autour: widget.positionPilote, vehicule: vehicule);
      case OuChercher.ici:
        await poi.chercher(autour: widget.centreCarte, vehicule: vehicule);
      case OuChercher.destination:
        await poi.chercher(autour: widget.destination, vehicule: vehicule);
      case OuChercher.leLongDeLaRoute:
        await poi.chercher(leLongDe: widget.itineraire, vehicule: vehicule);
    }
    if (navigateur.canPop()) navigateur.pop();
  }
}
