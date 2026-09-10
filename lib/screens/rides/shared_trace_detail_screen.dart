import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../models/shared_trace.dart';
import '../../providers/rides_provider.dart';
import '../../services/ride_repository.dart';
import '../../services/shared_trace_importer.dart';
import '../../services/shared_traces_api_client.dart';
import 'report_trace_sheet.dart';

/// Fiche d'une trace du catalogue partagé : aperçu, description, compteur de
/// téléchargements, puis les deux actions du rider — télécharger la trace
/// dans ses sorties, ou la signaler.
class SharedTraceDetailScreen extends StatefulWidget {
  const SharedTraceDetailScreen({super.key, required this.traceId, required this.api});

  final String traceId;
  final SharedTracesApiClient api;

  @override
  State<SharedTraceDetailScreen> createState() => _SharedTraceDetailScreenState();
}

class _SharedTraceDetailScreenState extends State<SharedTraceDetailScreen> {
  late final Future<SharedTraceDetail> _ficheFuture = widget.api.detail(widget.traceId);

  // Une fois vraie, ne revient jamais en arrière : la sortie créée est
  // définitive, même si le catalogue change d'avis sur la trace ensuite.
  bool _telechargee = false;
  bool _enCours = false;

  Future<void> _telecharger(SharedTraceDetail fiche) async {
    // Le seul ternaire d'onPressed ne suffit pas : il ne prend effet qu'à
    // la prochaine reconstruction, donc deux appuis dans la même frame
    // passeraient tous les deux et créeraient chacun leur propre sortie.
    if (_enCours || _telechargee) return;
    setState(() => _enCours = true);
    try {
      final gpx = await widget.api.downloadGpx(fiche.id);
      if (!mounted) return;
      final repo = context.read<RideRepository>();
      await SharedTraceImporter(repo).import(fiche, gpx);
      if (!mounted) return;
      await context.read<RidesProvider>().refresh();
      if (!mounted) return;
      setState(() => _telechargee = true);
    } on SharedTracesException catch (e) {
      _afficherErreur(e.message);
    } on FormatException {
      _afficherErreur("Cette trace n'a pas pu être téléchargée : fichier illisible.");
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  void _afficherErreur(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signaler(SharedTraceDetail fiche) =>
      showReportTraceSheet(context, traceId: fiche.id, api: widget.api);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trace partagée')),
      body: FutureBuilder<SharedTraceDetail>(
        future: _ficheFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final erreur = snap.error;
            final message =
                erreur is SharedTracesException ? erreur.message : 'Impossible de charger cette trace.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(message, textAlign: TextAlign.center),
              ),
            );
          }
          return _contenu(snap.data!);
        },
      ),
    );
  }

  Widget _contenu(SharedTraceDetail fiche) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(height: 200, child: _apercu(fiche)),
        const SizedBox(height: 16),
        Text(fiche.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Par ${fiche.authorName}'),
        const SizedBox(height: 12),
        _statistiques(fiche),
        const SizedBox(height: 12),
        Text(fiche.description),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.download_outlined, size: 18),
            const SizedBox(width: 4),
            Text('${fiche.downloadCount} téléchargements'),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _telechargee || _enCours ? null : () => _telecharger(fiche),
          icon: Icon(_telechargee ? Icons.check : Icons.download),
          label: Text(_telechargee ? 'Dans tes sorties' : 'Télécharger'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _signaler(fiche),
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Signaler'),
        ),
      ],
    );
  }

  // Même construction que le tracé de guidage de map_screen.dart : un
  // FlutterMap avec un unique PolylineLayer, pas de second mécanisme de
  // dessin pour une simple prévisualisation.
  Widget _apercu(SharedTraceDetail fiche) {
    if (fiche.preview.isEmpty) {
      return const Center(child: Text('Aperçu indisponible'));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: fiche.preview[fiche.preview.length ~/ 2],
          initialZoom: 12,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'app.motooffroad',
          ),
          PolylineLayer(polylines: [
            Polyline(points: fiche.preview, strokeWidth: 4, color: AppColors.navRoute),
          ]),
        ],
      ),
    );
  }

  Widget _statistiques(SharedTraceDetail fiche) {
    final km = (fiche.distanceM / 1000).toStringAsFixed(1).replaceAll('.', ',');
    final denivele = fiche.elevationGainM;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        Text('$km km'),
        Text(fiche.difficulty.libelle),
        Text(fiche.vehicle.libelle),
        if (denivele != null) Text('+${denivele.round()} m'),
      ],
    );
  }
}
