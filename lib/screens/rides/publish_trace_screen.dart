import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../models/ride.dart';
import '../../models/shared_trace.dart';
import '../../providers/rides_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/legal_documents.dart';
import '../../services/shared_traces_api_client.dart';
import '../../services/trace_crop_service.dart';

/// Écran de publication d'une sortie dans le catalogue partagé : recadrage
/// (le début d'une sortie enregistrée passe presque toujours devant chez le
/// pilote), fiche à remplir, puis acceptation explicite des conditions de
/// publication avant l'envoi.
class PublishTraceScreen extends StatefulWidget {
  const PublishTraceScreen({super.key, required this.rideId, required this.api});

  final String rideId;
  final SharedTracesApiClient api;

  @override
  State<PublishTraceScreen> createState() => _PublishTraceScreenState();
}

class _PublishTraceScreenState extends State<PublishTraceScreen> {
  static const _cleAvertissementVu = 'partage_avertissement_vu';

  late final TextEditingController _nomController;
  final _descriptionController = TextEditingController();
  late final TextEditingController _auteurController;

  List<RidePoint>? _points;
  int _indexDebut = 0;
  int _indexFin = 0;

  TraceVehicle _engin = TraceVehicle.moto;
  TraceDifficulty _difficulte = TraceDifficulty.facile;
  bool _accepteConditions = false;
  bool _publicationEnCours = false;
  String? _erreurDescription;
  String? _erreurServeur;

  @override
  void initState() {
    super.initState();
    final ride = context.read<RidesProvider>().rides.where((r) => r.id == widget.rideId).firstOrNull;
    _nomController = TextEditingController(text: ride?.name ?? '');
    _auteurController = TextEditingController(text: context.read<SettingsProvider>().riderName);
    _chargerPoints();
    // Après la première frame seulement : showDialog a besoin d'un
    // BuildContext déjà inséré dans l'arbre (Navigator, Overlay…).
    WidgetsBinding.instance.addPostFrameCallback((_) => _proposerAvertissement());
  }

  @override
  void dispose() {
    _nomController.dispose();
    _descriptionController.dispose();
    _auteurController.dispose();
    super.dispose();
  }

  Future<void> _chargerPoints() async {
    final points = await context.read<RidesProvider>().pointsOf(widget.rideId);
    if (!mounted) return;
    setState(() {
      _points = points;
      _indexDebut = 0;
      _indexFin = points.isEmpty ? 0 : points.length - 1;
    });
  }

  // Affiché une seule fois par installation : la préférence retient qu'il a
  // déjà été vu, même à travers plusieurs sorties publiées ensuite.
  Future<void> _proposerAvertissement() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_cleAvertissementVu) == true) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Avant de publier'),
        content: const Text(
          "Ta trace commence peut-être devant chez toi. Fais glisser le curseur "
          "de début pour publier seulement la partie qui t'intéresse.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Compris')),
        ],
      ),
    );
    await prefs.setBool(_cleAvertissementVu, true);
  }

  Future<void> _ouvrirConditions() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const _ConditionsPublicationScreen(),
    ));
  }

  Future<void> _publier(Ride ride, List<RidePoint> points) async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      setState(() => _erreurDescription = 'La description est obligatoire.');
      return;
    }

    setState(() {
      _erreurDescription = null;
      _erreurServeur = null;
      _publicationEnCours = true;
    });

    try {
      final gpx = TraceCropService.cropToGpx(
        ride,
        points,
        startIndex: _indexDebut,
        endIndex: _indexFin,
        name: _nomController.text.trim(),
        description: description,
      );
      await widget.api.publish(
        name: _nomController.text.trim(),
        description: description,
        authorName: _auteurController.text.trim(),
        vehicle: _engin,
        difficulty: _difficulte,
        gpx: gpx,
        // Explicite plutôt que laissé au défaut du client : c'est la trace
        // écrite du consentement du pilote, elle ne doit jamais dépendre en
        // silence de la valeur par défaut d'un paramètre défini ailleurs.
        licenceVersion: SharedTracesApiClient.licenceVersion,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ta trace est publiée.')),
      );
    } on SharedTracesException catch (e) {
      // L'échec laisse le rider sur l'écran, saisie intacte : perdre une
      // fiche remplie pour un simple accroc réseau serait sa propre petite
      // trahison.
      setState(() {
        _erreurServeur = e.message;
        _publicationEnCours = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.watch<RidesProvider>().rides.where((r) => r.id == widget.rideId).firstOrNull;
    if (ride == null) {
      return const Scaffold(body: Center(child: Text('Sortie introuvable')));
    }
    final points = _points;
    // Une trace coupée par un crash de l'enregistrement ou un import avorté
    // peut laisser une sortie à 0 ou 1 point : ni _apercu (sublist, point
    // central) ni le recadrage n'ont de sens en dessous de 2 points, donc ce
    // cas sort avant que quoi que ce soit ne touche `points`.
    final Widget corps;
    if (points == null) {
      corps = const Center(child: CircularProgressIndicator());
    } else if (points.length < 2) {
      corps = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Cette sortie n'a pas assez de points pour être publiée.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      corps = _formulaire(ride, points);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Publier la trace')),
      body: corps,
    );
  }

  // N'est appelée que pour une sortie d'au moins 2 points (voir build) :
  // _apercu et le recadrage supposent tous deux cette borne.
  Widget _formulaire(Ride ride, List<RidePoint> points) {
    final peutPublier = _accepteConditions && !_publicationEnCours;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(height: 200, child: _apercu(points)),
        const SizedBox(height: 16),
        _curseurs(points),
        const SizedBox(height: 16),
        TextField(
          controller: _nomController,
          decoration: const InputDecoration(labelText: 'Nom de la trace'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('champ_description'),
          controller: _descriptionController,
          maxLines: 3,
          decoration: InputDecoration(labelText: 'Description', errorText: _erreurDescription),
          onChanged: (_) {
            if (_erreurDescription != null) setState(() => _erreurDescription = null);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _auteurController,
          decoration: const InputDecoration(labelText: "Nom d'auteur affiché"),
        ),
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
        _conditions(),
        if (_erreurServeur != null) ...[
          const SizedBox(height: 12),
          Text(_erreurServeur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: peutPublier ? () => _publier(ride, points) : null,
            child: _publicationEnCours
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Publier'),
          ),
        ),
      ],
    );
  }

  // Même construction que shared_trace_detail_screen.dart : un FlutterMap
  // avec un unique PolylineLayer. Les deux extrémités rognées apparaissent
  // en gris, la portion retenue en couleur pleine.
  Widget _apercu(List<RidePoint> points) {
    final avant = points.sublist(0, _indexDebut + 1).map((p) => p.position).toList();
    final retenue = points.sublist(_indexDebut, _indexFin + 1).map((p) => p.position).toList();
    final apres = points.sublist(_indexFin).map((p) => p.position).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: points[points.length ~/ 2].position,
          initialZoom: 12,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.motooffroad.app',
          ),
          PolylineLayer(polylines: [
            if (avant.length > 1) Polyline(points: avant, strokeWidth: 4, color: Colors.grey),
            if (apres.length > 1) Polyline(points: apres, strokeWidth: 4, color: Colors.grey),
            if (retenue.length > 1) Polyline(points: retenue, strokeWidth: 4, color: AppColors.navRoute),
          ]),
        ],
      ),
    );
  }

  Widget _curseurs(List<RidePoint> points) {
    final maxIndex = points.length - 1;
    final km = TraceCropService.distanceOf(points, _indexDebut, _indexFin) / 1000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Début du tracé publié'),
        Slider(
          key: const Key('curseur_debut'),
          value: _indexDebut.toDouble(),
          min: 0,
          max: maxIndex.toDouble(),
          divisions: maxIndex,
          onChanged: (v) => setState(() => _indexDebut = v.round().clamp(0, _indexFin - 1)),
        ),
        const Text('Fin du tracé publié'),
        Slider(
          key: const Key('curseur_fin'),
          value: _indexFin.toDouble(),
          min: 0,
          max: maxIndex.toDouble(),
          divisions: maxIndex,
          onChanged: (v) => setState(() => _indexFin = v.round().clamp(_indexDebut + 1, maxIndex)),
        ),
        Text('${km.toStringAsFixed(1).replaceAll('.', ',')} km retenus'),
      ],
    );
  }

  Widget _conditions() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          key: const Key('case_acceptation'),
          value: _accepteConditions,
          onChanged: _publicationEnCours ? null : (v) => setState(() => _accepteConditions = v ?? false),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text("J'accepte les "),
                  GestureDetector(
                    onTap: _ouvrirConditions,
                    child: const Text(
                      'conditions de publication',
                      style: TextStyle(decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Ma trace restera au catalogue même si je supprime mon compte.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Texte complet des conditions ─────────────────────────────
//
// Une seule maison pour ce texte : LegalDocuments, jamais recopié en dur
// dans le code Dart, pour qu'une correction n'ait jamais à être faite à
// deux endroits.
class _ConditionsPublicationScreen extends StatefulWidget {
  const _ConditionsPublicationScreen();

  @override
  State<_ConditionsPublicationScreen> createState() => _ConditionsPublicationScreenState();
}

class _ConditionsPublicationScreenState extends State<_ConditionsPublicationScreen> {
  // Chargé une seule fois en mémoire (pas dans build()) : recréer ce Future
  // à chaque build() ferait repasser le FutureBuilder en chargement à
  // chaque reconstruction — voir la même remarque, plus détaillée, sur
  // CharteScreen._charte. Champ mutable pour permettre un nouvel essai si
  // la ressource embarquée échoue à charger.
  Future<String> _texte = LegalDocuments.conditionsPublication();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conditions de publication')),
      body: FutureBuilder<String>(
        future: _texte,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Impossible de charger les conditions de publication.', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() => _texte = LegalDocuments.conditionsPublication()),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(snap.data!),
          );
        },
      ),
    );
  }
}
