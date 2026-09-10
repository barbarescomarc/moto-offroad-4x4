import 'package:flutter/material.dart';

import '../../services/shared_traces_api_client.dart';

// ── Motifs affichés, dans l'ordre, avec leur valeur serveur ──
const _motifs = <(String valeur, String libelle)>[
  ('terrain_prive', 'Terrain privé'),
  ('dangereux', 'Dangereux'),
  ('doublon', 'Doublon'),
  ('inapproprie', 'Contenu inapproprié'),
  ('autre', 'Autre'),
];

/// Ouvre la feuille de signalement d'une trace. Rend `true` si un
/// signalement est effectivement parti (la feuille se ferme alors d'elle
/// même) ; `false` si le rider l'a refermée sans envoyer.
Future<bool> showReportTraceSheet(
  BuildContext context, {
  required String traceId,
  required SharedTracesApiClient api,
}) async {
  final envoye = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _ReportTraceSheet(traceId: traceId, api: api),
  );
  return envoye ?? false;
}

class _ReportTraceSheet extends StatefulWidget {
  const _ReportTraceSheet({required this.traceId, required this.api});

  final String traceId;
  final SharedTracesApiClient api;

  @override
  State<_ReportTraceSheet> createState() => _ReportTraceSheetState();
}

class _ReportTraceSheetState extends State<_ReportTraceSheet> {
  final _detailController = TextEditingController();
  String? _motif;
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final motif = _motif;
    if (motif == null) return;

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    final detail = _detailController.text.trim();
    try {
      await widget.api.report(widget.traceId, reason: motif, detail: detail.isEmpty ? null : detail);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci, le signalement est parti.')),
      );
    } on SharedTracesException catch (e) {
      // L'échec reste affiché dans la feuille, qui reste ouverte : ne pas
      // avaler ce message (ex. « Tu as déjà signalé cette trace. ») en la
      // refermant comme si de rien n'était.
      setState(() {
        _erreur = e.message;
        _enCours = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signaler cette trace', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _motif,
              onChanged: (v) => setState(() => _motif = v),
              child: Column(
                children: [
                  for (final (valeur, libelle) in _motifs)
                    RadioListTile<String>(title: Text(libelle), value: valeur),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: _detailController,
                decoration: const InputDecoration(labelText: 'Précision (facultatif)'),
              ),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _motif == null || _enCours ? null : _envoyer,
                child: const Text('Envoyer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
