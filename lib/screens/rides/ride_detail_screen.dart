import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/ride.dart';
import '../../providers/rides_provider.dart';

class RideDetailScreen extends StatelessWidget {
  const RideDetailScreen({super.key, required this.rideId});
  final String rideId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RidesProvider>();
    final ride = provider.rides.where((r) => r.id == rideId).firstOrNull;
    if (ride == null) {
      return const Scaffold(body: Center(child: Text('Sortie introuvable')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(ride.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Renommer',
            onPressed: () => _rename(context, ride),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Supprimer',
            onPressed: () => _confirmDelete(context, ride),
          ),
        ],
      ),
      body: FutureBuilder<List<RidePoint>>(
        future: provider.pointsOf(rideId),
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              SizedBox(height: 280, child: _RideMap(points: snap.data!)),
              Expanded(child: _StatsList(ride: ride)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _rename(BuildContext context, Ride ride) async {
    final controller = TextEditingController(text: ride.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer la sortie'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      await context.read<RidesProvider>().rename(ride.id, name);
    }
  }

  Future<void> _confirmDelete(BuildContext context, Ride ride) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette sortie ?'),
        content: Text('« ${ride.name} » et sa trace seront définitivement '
            'effacées.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<RidesProvider>().remove(ride.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

// ── Carte de la sortie : une polyligne par segment ───────────
class _RideMap extends StatelessWidget {
  const _RideMap({required this.points});
  final List<RidePoint> points;

  // Deux segments ne sont jamais reliés : le trajet fait pendant une pause
  // n'a pas été enregistré et un trait droit mentirait sur le parcours.
  List<List<LatLng>> get _segments {
    final result = <List<LatLng>>[];
    List<LatLng>? current;
    int? currentSegment;
    for (final p in points) {
      if (p.segment != currentSegment) {
        if (current != null) result.add(current);
        current = [];
        currentSegment = p.segment;
      }
      current!.add(p.position);
    }
    if (current != null) result.add(current);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('Aucun point enregistré'));
    }
    return FlutterMap(
      options: MapOptions(
        initialCenter: points[points.length ~/ 2].position,
        initialZoom: 12,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.motooffroad.app',
        ),
        PolylineLayer(
          polylines: _segments
              .map((seg) => Polyline(
                    points: seg,
                    strokeWidth: 4,
                    color: const Color(0xFFEF5350),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _StatsList extends StatelessWidget {
  const _StatsList({required this.ride});
  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final s = ride.stats;
    final total = s.totalTime;
    final moving = s.movingTime;
    return ListView(
      children: [
        _row('Distance',
            '${s.distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km'),
        _row('Durée totale',
            '${total.inHours}h${(total.inMinutes % 60).toString().padLeft(2, '0')}'),
        _row('Temps en mouvement',
            '${moving.inHours}h${(moving.inMinutes % 60).toString().padLeft(2, '0')}'),
        _row('Vitesse moyenne', '${s.avgSpeedKmh.toStringAsFixed(1)} km/h'),
        _row('Vitesse maximale', '${s.maxSpeedKmh.toStringAsFixed(1)} km/h'),
        _row('Origine',
            ride.source == RideSource.recorded ? 'Enregistrée' : 'Importée'),
      ],
    );
  }

  Widget _row(String label, String value) => ListTile(
        dense: true,
        title: Text(label),
        trailing: Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      );
}
