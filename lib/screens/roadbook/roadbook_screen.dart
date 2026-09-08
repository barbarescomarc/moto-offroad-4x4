// lib/screens/roadbook/roadbook_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../models/roadbook_entry.dart';
import '../../models/trace.dart';
import '../../providers/trace_provider.dart';
import '../../services/gpx_route_deriver.dart';
import '../../widgets/maneuver_icon.dart';

// Lecture façon carnet de rallye de la trace active : cap, distance
// partielle, distance cumulée, pictogramme de manœuvre — pas les phrases
// parlées du guidage classique.
class RoadbookScreen extends StatefulWidget {
  const RoadbookScreen({super.key});

  @override
  State<RoadbookScreen> createState() => _RoadbookScreenState();
}

class _RoadbookScreenState extends State<RoadbookScreen> {
  TraceModel? _trace;
  List<RoadbookEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    final trace = context.read<TraceProvider>().activeTrace;
    _trace = trace;
    _entries = trace == null ? const [] : GpxRouteDeriver.deriveRoadbook(trace);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(title: Text(_trace?.name.toUpperCase() ?? 'ROADBOOK')),
      body: _entries.isEmpty
          ? const Center(
              child: Text('Aucune trace chargée', style: TextStyle(color: Colors.white54)),
            )
          : ListView.separated(
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const Divider(color: Color(0xFF2A2A3E), height: 1),
              itemBuilder: (_, i) => _entryRow(_entries[i]),
            ),
    );
  }

  Widget _entryRow(RoadbookEntry entry) {
    return ListTile(
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: .15),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.orange.withValues(alpha: .5)),
        ),
        alignment: Alignment.center,
        child: Icon(maneuverIcon(entry.maneuver), color: AppColors.orange),
      ),
      title: Row(
        children: [
          Text(
            '${entry.capDeg.round().toString().padLeft(3, '0')}°',
            style: const TextStyle(color: Colors.white, fontFamily: 'Rajdhani',
              fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(width: 12),
          Text(_distanceLabel(entry.partialDistanceMeters),
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Text(_distanceLabel(entry.cumulativeDistanceMeters),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
      subtitle: GestureDetector(
        onTap: () => _editNote(entry),
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            (entry.note?.isNotEmpty ?? false) ? entry.note! : 'Ajouter une note…',
            style: TextStyle(
              color: (entry.note?.isNotEmpty ?? false) ? Colors.white54 : AppColors.textMuted,
              fontStyle: FontStyle.italic, fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editNote(RoadbookEntry entry) async {
    final ctrl = TextEditingController(text: entry.note);
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        title: const Text('Note', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl, autofocus: true, maxLines: 3,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (note == null) return;
    final idx = _entries.indexOf(entry);
    setState(() => _entries[idx] = entry.copyWith(note: note));
  }

  static String _distanceLabel(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }
}
