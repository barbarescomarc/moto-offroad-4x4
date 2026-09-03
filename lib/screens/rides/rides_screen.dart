import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/router.dart';
import '../../models/ride.dart';
import '../../providers/rides_provider.dart';
import '../../services/ride_database.dart';

class RidesScreen extends StatefulWidget {
  const RidesScreen({super.key});

  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen> {
  Ride? _unfinishedRide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<RidesProvider>();
      await provider.refresh();
      final open = await provider.findUnfinished();
      if (mounted && open != null) {
        setState(() => _unfinishedRide = open);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RidesProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('🏍️  SORTIES')),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.rides.isEmpty
              ? const _EmptyState()
              : Column(
                  children: [
                    // Bandeau de récupération après plantage
                    if (_unfinishedRide != null)
                      _recoveryBanner(_unfinishedRide!),
                    // Liste des sorties
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: provider.refresh,
                        child: ListView.separated(
                          itemCount: provider.rides.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => _RideTile(ride: provider.rides[i]),
                        ),
                      ),
                    ),
                    // Pied de page avec espace disque
                    _storageFooter(provider),
                  ],
                ),
    );
  }

  // Bandeau proposant de clôturer une sortie interrompue
  Widget _recoveryBanner(Ride ride) => MaterialBanner(
    content: Text('La sortie « ${ride.name} » a été interrompue.'),
    leading: const Icon(Icons.warning_amber),
    actions: [
      TextButton(
        onPressed: () async {
          await context.read<RidesProvider>().closeUnfinished(ride);
          if (mounted) {
            setState(() => _unfinishedRide = null);
          }
        },
        child: const Text('Clôturer'),
      ),
      TextButton(
        onPressed: () async {
          await context.read<RidesProvider>().remove(ride.id);
          if (mounted) {
            setState(() => _unfinishedRide = null);
          }
        },
        child: const Text('Supprimer'),
      ),
    ],
  );

  // Pied de page affichant l'espace occupé par les sorties
  Widget _storageFooter(RidesProvider provider) => FutureBuilder<int>(
    future: RideDatabase.sizeBytes(),
    builder: (_, snap) {
      if (!snap.hasData) return const SizedBox.shrink();
      final mo = snap.data! / (1024 * 1024);
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          '${provider.rides.length} sorties · '
          '${mo.toStringAsFixed(1).replaceAll('.', ',')} Mo occupés',
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
      );
    },
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Aucune sortie pour l\'instant.\n\n'
            'Appuyez sur ENREGISTRER depuis la carte pour garder la trace '
            'de votre prochaine balade.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _RideTile extends StatelessWidget {
  const _RideTile({required this.ride});
  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final d = ride.stats.totalTime;
    return ListTile(
      leading: Icon(
        ride.source == RideSource.recorded
            ? Icons.fiber_manual_record
            : Icons.download,
        color: ride.source == RideSource.recorded
            ? const Color(0xFFEF5350)
            : const Color(0xFF5C6BC0),
      ),
      title: Text(ride.name),
      subtitle: Text(
        '${ride.startedAt.day}/${ride.startedAt.month}/${ride.startedAt.year}'
        ' · ${ride.stats.distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km'
        ' · ${d.inHours}h${(d.inMinutes % 60).toString().padLeft(2, '0')}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('${AppRoutes.rides}/${ride.id}'),
    );
  }
}
