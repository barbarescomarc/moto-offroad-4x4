import 'package:flutter/material.dart';

import '../../models/shared_trace.dart';
import '../../services/shared_traces_api_client.dart';

/// Écran « Mes publications » : ce qu'un rider a partagé au catalogue,
/// combien de riders l'ont téléchargé, et si la modération l'a retirée.
///
/// `mine()` renvoie des `SharedTraceSummary` — pas de description complète
/// (réservée à la fiche détaillée d'un rider tiers) : le formulaire de
/// modification ci-dessous en tient compte, sa description part vide plutôt
/// que de mentir sur le texte actuellement publié.
class MyPublicationsScreen extends StatefulWidget {
  const MyPublicationsScreen({super.key, required this.api});

  final SharedTracesApiClient api;

  @override
  State<MyPublicationsScreen> createState() => _MyPublicationsScreenState();
}

class _MyPublicationsScreenState extends State<MyPublicationsScreen> {
  late Future<List<SharedTraceSummary>> _futur;

  @override
  void initState() {
    super.initState();
    _futur = widget.api.mine();
  }

  Future<void> _rafraichir() async {
    final futur = widget.api.mine();
    // Accolades nécessaires : `() => _futur = futur` vaudrait la valeur de
    // l'affectation elle-même (un Future), que setState refuse comme
    // argument de son callback.
    setState(() {
      _futur = futur;
    });
    await futur;
  }

  Future<void> _modifier(SharedTraceSummary trace) async {
    final champs = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _FormulaireModification(trace: trace),
    );
    // Aucun champ modifié : ni ouverture annulée (résultat null), ni
    // formulaire enregistré tel quel (map vide) ne justifient un appel
    // serveur — voir la décision "seuls les champs changés partent".
    if (champs == null || champs.isEmpty || !mounted) return;
    await widget.api.update(
      trace.id,
      name: champs['name'] as String?,
      description: champs['description'] as String?,
      authorName: champs['authorName'] as String?,
      vehicle: champs['vehicle'] as TraceVehicle?,
      difficulty: champs['difficulty'] as TraceDifficulty?,
    );
    if (!mounted) return;
    await _rafraichir();
  }

  Future<void> _depublier(SharedTraceSummary trace) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dépublier cette trace ?'),
        content: const Text(
          "Elle disparaîtra du catalogue partagé. Les riders qui l'ont déjà "
          'téléchargée la gardent : dépublier ne la leur retire pas.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Dépublier définitivement'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    await widget.api.unpublish(trace.id);
    if (!mounted) return;
    await _rafraichir();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes publications')),
      body: FutureBuilder<List<SharedTraceSummary>>(
        future: _futur,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final traces = snap.data!;
          if (traces.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text("Tu n'as encore rien publié.", textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: traces.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _FicheTile(
              trace: traces[i],
              onModifier: () => _modifier(traces[i]),
              onDepublier: () => _depublier(traces[i]),
            ),
          );
        },
      ),
    );
  }
}

class _FicheTile extends StatelessWidget {
  const _FicheTile({required this.trace, required this.onModifier, required this.onDepublier});

  final SharedTraceSummary trace;
  final VoidCallback onModifier;
  final VoidCallback onDepublier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(trace.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.download_outlined, size: 16),
                const SizedBox(width: 4),
                Text('${trace.downloadCount} téléchargements'),
              ],
            ),
            const SizedBox(height: 4),
            if (trace.hidden)
              Text(
                trace.hiddenReason == null
                    ? 'Retirée du partage'
                    : 'Retirée du partage — ${trace.hiddenReason}',
                style: TextStyle(color: scheme.error),
              )
            else
              const Text('Publiée', style: TextStyle(color: Colors.green)),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(onPressed: onModifier, child: const Text('Modifier la fiche')),
                TextButton(onPressed: onDepublier, child: const Text('Dépublier')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Mêmes champs que la publication (`PublishTraceScreen`), moins le
/// recadrage : le GPX ne change jamais après publication.
///
/// N'envoie que les champs réellement modifiés — name/authorName/engin/
/// difficulté sont comparés à la fiche connue ; la description, absente de
/// `SharedTraceSummary`, part vide : un rider qui ne la touche pas ne
/// l'écrase donc jamais avec du vide.
class _FormulaireModification extends StatefulWidget {
  const _FormulaireModification({required this.trace});

  final SharedTraceSummary trace;

  @override
  State<_FormulaireModification> createState() => _FormulaireModificationState();
}

class _FormulaireModificationState extends State<_FormulaireModification> {
  late final TextEditingController _nom;
  late final TextEditingController _description;
  late final TextEditingController _auteur;
  late TraceVehicle _engin;
  late TraceDifficulty _difficulte;

  @override
  void initState() {
    super.initState();
    _nom = TextEditingController(text: widget.trace.name);
    _description = TextEditingController();
    _auteur = TextEditingController(text: widget.trace.authorName);
    _engin = widget.trace.vehicle;
    _difficulte = widget.trace.difficulty;
  }

  @override
  void dispose() {
    _nom.dispose();
    _description.dispose();
    _auteur.dispose();
    super.dispose();
  }

  void _enregistrer() {
    final champs = <String, dynamic>{};
    if (_nom.text.trim() != widget.trace.name) champs['name'] = _nom.text.trim();
    if (_description.text.trim().isNotEmpty) champs['description'] = _description.text.trim();
    if (_auteur.text.trim() != widget.trace.authorName) champs['authorName'] = _auteur.text.trim();
    if (_engin != widget.trace.vehicle) champs['vehicle'] = _engin;
    if (_difficulte != widget.trace.difficulty) champs['difficulty'] = _difficulte;
    Navigator.of(context).pop(champs);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Modifier la fiche', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: _nom, decoration: const InputDecoration(labelText: 'Nom de la trace')),
            const SizedBox(height: 12),
            TextField(
              key: const Key('champ_description'),
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Laisser vide pour ne pas la modifier',
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: _auteur, decoration: const InputDecoration(labelText: "Nom d'auteur affiché")),
            const SizedBox(height: 16),
            Text('Engin', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            SegmentedButton<TraceVehicle>(
              segments: [for (final v in TraceVehicle.values) ButtonSegment(value: v, label: Text(v.libelle))],
              selected: {_engin},
              onSelectionChanged: (s) => setState(() => _engin = s.first),
            ),
            const SizedBox(height: 16),
            Text('Difficulté', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            SegmentedButton<TraceDifficulty>(
              segments: [for (final d in TraceDifficulty.values) ButtonSegment(value: d, label: Text(d.libelle))],
              selected: {_difficulte},
              onSelectionChanged: (s) => setState(() => _difficulte = s.first),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _enregistrer, child: const Text('Enregistrer')),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
