import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../models/favorite_place.dart';
import '../../models/shared_trace.dart';
import '../../providers/shared_traces_provider.dart';
import '../../services/location_service.dart';
import '../../widgets/map_search_bar.dart';

/// Rayons de recherche proposés autour du point de référence.
const _rayonsKm = [10.0, 25.0, 50.0, 100.0, 200.0];

/// Volet « Partagées » de l'onglet Sorties : recherche dans le catalogue de
/// traces publiées par d'autres riders, autour d'un point de référence.
///
/// Ne demande jamais de permission de localisation : le mur d'inscription du
/// lot A (correctif I7) a déjà réglé cette question, et la redemander depuis
/// un onglet de liste serait une régression. Ce volet se contente de la
/// dernière position connue de [LocationService] ; si elle n'existe pas
/// encore, le rider choisit un lieu via le sélecteur de favoris.
class SharedTracesPanel extends StatefulWidget {
  const SharedTracesPanel({super.key});

  @override
  State<SharedTracesPanel> createState() => _SharedTracesPanelState();
}

class _SharedTracesPanelState extends State<SharedTracesPanel> {
  final _rechercheController = TextEditingController();
  bool _amorce = false;

  @override
  void initState() {
    super.initState();
    // Une seule tentative d'amorçage par ouverture du volet : ensuite, seul
    // un geste du rider (choisir un lieu, changer un filtre) doit relancer
    // une recherche.
    WidgetsBinding.instance.addPostFrameCallback((_) => _amorcerReference());
  }

  @override
  void dispose() {
    _rechercheController.dispose();
    super.dispose();
  }

  void _amorcerReference() {
    if (_amorce || !mounted) return;
    _amorce = true;
    final provider = context.read<SharedTracesProvider>();
    if (provider.reference != null) return;

    final derniere = LocationService().lastSnapshot;
    if (derniere != null) {
      provider.setReference(derniere.position);
    } else {
      // Pas de position connue : refresh() pose "Position inconnue" sans
      // tenter de requête — voir SharedTracesProvider.refresh().
      provider.refresh();
    }
  }

  // Deux façons de poser la référence, comme sur la carte (menu radial :
  // loupe de recherche et étoile des favoris, deux entrées distinctes) :
  // rechercher une adresse, ou reprendre un favori déjà enregistré. Sans la
  // recherche, un rider sans favori et sans position connue — justement
  // celui qui en a le plus besoin — ne pourrait jamais poser de référence.
  Future<void> _choisirLieu() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Rechercher un lieu'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _rechercherLieu();
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_border),
              title: const Text('Mes favoris'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _choisirFavori();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rechercherLieu() async {
    LatLng? position;
    String? label;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: MapSearchBar(
          // Jamais attaché à un FlutterMap — sans effet ici puisque
          // onSelect court-circuite tout appel à mapController.move().
          mapController: MapController(),
          startVisible: true,
          onResultSelected: () => Navigator.of(sheetContext).pop(),
          onSelect: (pos, resultLabel) {
            position = pos;
            label = resultLabel;
          },
        ),
      ),
    );
    if (position == null || !mounted) return;
    context.read<SharedTracesProvider>().setReference(position!, label: label);
  }

  Future<void> _choisirFavori() async {
    final lieu = await context.push<FavoritePlace>(AppRoutes.favorites);
    if (lieu == null || !mounted) return;
    context.read<SharedTracesProvider>().setReference(lieu.position, label: lieu.name);
  }

  Future<void> _choisirEngin(SharedTracesProvider provider) async {
    final choix = await showDialog<_ChoixEngin>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Engin'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(const _ChoixEngin(null)),
            child: const Text('Tous les engins'),
          ),
          for (final v in TraceVehicle.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(_ChoixEngin(v)),
              child: Text(v.libelle),
            ),
        ],
      ),
    );
    if (choix == null || !mounted) return;
    provider.setVehicle(choix.valeur);
  }

  Future<void> _choisirDifficulte(SharedTracesProvider provider) async {
    final choix = await showDialog<_ChoixDifficulte>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Difficulté'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(const _ChoixDifficulte(null)),
            child: const Text('Toutes difficultés'),
          ),
          for (final d in TraceDifficulty.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(_ChoixDifficulte(d)),
              child: Text(d.libelle),
            ),
        ],
      ),
    );
    if (choix == null || !mounted) return;
    provider.setDifficulty(choix.valeur);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SharedTracesProvider>();
    return Column(
      children: [
        _ligneReference(provider),
        _filtres(provider),
        Expanded(child: _liste(provider)),
      ],
    );
  }

  Widget _ligneReference(SharedTracesProvider provider) {
    final String libelle;
    if (provider.referenceLabel != null) {
      libelle = provider.referenceLabel!;
    } else if (provider.reference != null) {
      libelle = 'Autour de ma position';
    } else {
      libelle = 'Position inconnue';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(libelle, overflow: TextOverflow.ellipsis)),
          TextButton(
            onPressed: _choisirLieu,
            child: const Text('Choisir un lieu'),
          ),
        ],
      ),
    );
  }

  Widget _filtres(SharedTracesProvider provider) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Rayon : '),
                DropdownButton<double>(
                  value: provider.radiusKm,
                  items: [
                    for (final km in _rayonsKm)
                      DropdownMenuItem(value: km, child: Text('${km.round()} km')),
                  ],
                  onChanged: (km) {
                    if (km != null) provider.setRadius(km);
                  },
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: Text(provider.vehicle?.libelle ?? 'Tous les engins'),
                  selected: provider.vehicle != null,
                  onSelected: (_) => _choisirEngin(provider),
                ),
                FilterChip(
                  label: Text(provider.difficulty?.libelle ?? 'Toutes difficultés'),
                  selected: provider.difficulty != null,
                  onSelected: (_) => _choisirDifficulte(provider),
                ),
              ],
            ),
            TextField(
              controller: _rechercheController,
              decoration: const InputDecoration(hintText: 'Rechercher une trace'),
              onSubmitted: provider.setQuery,
            ),
            const SizedBox(height: 4),
          ],
        ),
      );

  Widget _liste(SharedTracesProvider provider) {
    if (provider.isLoading && provider.traces.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null && provider.traces.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(provider.error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (provider.traces.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucune trace partagée dans ce rayon.', textAlign: TextAlign.center),
        ),
      );
    }

    // Des résultats existent déjà : ni une panne ni un rechargement ne
    // doivent les effacer — une liste un peu périmée vaut mieux qu'un écran
    // vide en pleine cambrousse. Mais le rider doit pouvoir voir qu'elle
    // l'est : un bandeau pour l'erreur, une barre fine pour le chargement en
    // cours, jamais les deux en silence.
    return Column(
      children: [
        if (provider.error != null) _bandeauPerime(provider.error!),
        if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView.separated(
            itemCount: provider.traces.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _TraceTile(trace: provider.traces[i]),
          ),
        ),
      ],
    );
  }

  Widget _bandeauPerime(String message) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 16, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

// Enveloppe distinguant « le rider a choisi 'tous' » (valeur null explicite)
// de « la boîte de dialogue a été fermée sans choix » (résultat null tout
// court) : sans elle, showDialog<TraceVehicle?> ne peut pas faire la
// différence entre les deux, et un appui hors du dialogue effacerait le
// filtre au lieu de ne rien faire.
class _ChoixEngin {
  const _ChoixEngin(this.valeur);
  final TraceVehicle? valeur;
}

class _ChoixDifficulte {
  const _ChoixDifficulte(this.valeur);
  final TraceDifficulty? valeur;
}

class _TraceTile extends StatelessWidget {
  const _TraceTile({required this.trace});
  final SharedTraceSummary trace;

  @override
  Widget build(BuildContext context) {
    final longueur = (trace.distanceM / 1000).toStringAsFixed(1).replaceAll('.', ',');
    final distanceRef = trace.distanceFromRefM;
    final sousTitre = StringBuffer()
      ..write(trace.authorName)
      ..write(' · $longueur km')
      ..write(' · ${trace.difficulty.libelle}')
      ..write(' · ${trace.vehicle.libelle}');
    if (distanceRef != null) {
      sousTitre.write(' · à ${(distanceRef / 1000).round()} km');
    }
    return ListTile(
      title: Text(trace.name),
      subtitle: Text(sousTitre.toString()),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.download_outlined, size: 16),
          const SizedBox(width: 4),
          Text('${trace.downloadCount}'),
        ],
      ),
    );
  }
}
