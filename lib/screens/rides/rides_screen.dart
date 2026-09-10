import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/router.dart';
import '../../models/ride.dart';
import '../../providers/rides_provider.dart';
import '../../services/ride_database.dart';
import 'shared_traces_panel.dart';

class RidesScreen extends StatefulWidget {
  const RidesScreen({super.key});

  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen> {
  // 0 : sorties enregistrées localement · 1 : catalogue partagé.
  int _volet = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🏍️  SORTIES')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Mes sorties')),
                ButtonSegment(value: 1, label: Text('Partagées')),
              ],
              selected: {_volet},
              onSelectionChanged: (s) => setState(() => _volet = s.first),
            ),
          ),
          // IndexedStack, pas un ternaire : un ternaire démonterait puis
          // remonterait le volet caché à chaque bascule, ce qui relancerait
          // son initState (et donc un nouveau refresh()) à chaque fois —
          // une extraction n'est pas censée changer ce comportement.
          // SharedTracesPanel reçoit en plus estVisible : l'IndexedStack le
          // monte dès l'ouverture de l'onglet même si « Mes sorties » est
          // affiché, et sans ce drapeau son amorçage (position + requête
          // catalogue) partirait immédiatement au lieu d'attendre que le
          // rider bascule vraiment sur « Partagées ».
          Expanded(
            child: IndexedStack(
              index: _volet,
              children: [
                const MyRidesPanel(),
                SharedTracesPanel(estVisible: _volet == 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Volet « Mes sorties » ─────────────────────────────────────
// Extraction pure de l'ancien corps de RidesScreen : même contenu, même
// comportement, seule l'enveloppe (Scaffold + AppBar, désormais dans
// RidesScreen) a changé de place.
class MyRidesPanel extends StatefulWidget {
  const MyRidesPanel({super.key});

  @override
  State<MyRidesPanel> createState() => _MyRidesPanelState();
}

class _MyRidesPanelState extends State<MyRidesPanel> {
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
    return provider.isLoading
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
