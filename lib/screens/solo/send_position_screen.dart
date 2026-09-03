import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../providers/solo_provider.dart';
import '../../services/call_bridge.dart';
import '../../services/location_service.dart';
import '../../services/sos_service.dart';

class SendPositionScreen extends StatefulWidget {
  const SendPositionScreen({super.key});

  @override
  State<SendPositionScreen> createState() => _SendPositionScreenState();
}

class _SendPositionScreenState extends State<SendPositionScreen> {
  GpsSnapshot? _snapshot;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() => _loading = true);
    final snap = await LocationService().getCurrentPosition();
    if (mounted) setState(() { _snapshot = snap; _loading = false; });
  }

  String get _message =>
      'Je suis ici :\n${_snapshot!.sosText}\n\n${_snapshot!.googleMapsUrl}';

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _sendTo(TrustedContact contact) async {
    final ok = await CallBridge().sendSms(contact.phone, _message);
    _toast(ok
        ? 'Position envoyée à ${contact.name}'
        : "Échec de l'envoi à ${contact.name}");
  }

  @override
  Widget build(BuildContext context) {
    final solo = context.watch<SoloProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0A),
      appBar: AppBar(
        backgroundColor: AppColors.green,
        title: const Text('Envoyer ma position'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _positionCard(),
            const SizedBox(height: 16),
            if (_snapshot != null) ...[
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _snapshot!.googleMapsUrl));
                  _toast('Lien copié');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copier le lien Google Maps'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => SosService().shareGeneric(),
                icon: const Icon(Icons.share),
                label: const Text('Partager autrement'),
              ),
              const SizedBox(height: 24),
              const Text('ENVOYER PAR SMS',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12,
                  fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 8),
              if (solo.contacts.isEmpty) _noContacts()
              else ...solo.contacts.map((c) => ListTile(
                title: Text(c.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(c.phone,
                  style: const TextStyle(color: AppColors.textSecondary)),
                trailing: ElevatedButton(
                  onPressed: () => _sendTo(c),
                  child: const Text('Envoyer'),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _positionCard() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_snapshot == null) {
      return Column(
        children: [
          const Text('Position indisponible — vérifiez que le GPS est actif',
            style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _locate, child: const Text('Réessayer')),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_snapshot!.sosText,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
          const SizedBox(height: 8),
          Text('Mesurée à ${_snapshot!.timestamp.toLocal()}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  // Résolution 2 : on arrive depuis SoloScreen, donc un retour à l'écran
  // précédent évite d'empiler un doublon de solo par-dessus lui-même.
  Widget _noContacts() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Aucun contact de confiance enregistré',
        style: TextStyle(color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Retour'),
      ),
    ],
  );
}
