import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';
import '../../services/location_service.dart';
import '../../services/sos_service.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final _sosService  = SosService();
  GpsSnapshot? _snap;
  bool _loading = true;
  String? _copiedMsg;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final snap = await _sosService.getSnapshot();
    if (mounted) setState(() { _snap = snap; _loading = false; });
  }

  void _showCopied(String msg) {
    setState(() => _copiedMsg = msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedMsg = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Seul écran resté sombre après la reprise de la charte claire du
      // site (2026-09-15) : c'est un état d'alarme, pas une surface de
      // marque. Un fond blanc ici affaiblirait le signal, et l'écran doit
      // rester lisible de nuit, casque sur la tête, sans éblouir.
      backgroundColor: const Color(0xFF0D0000),
      appBar: AppBar(
        backgroundColor: AppColors.destructive,
        title: const Text('🆘  URGENCE — SOS',
          style: TextStyle(color: AppColors.onPrimary, fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.onPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Je vais bien', style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 12)),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.destructive))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // ── Coordonnées GPS ─────────────────────
                    _coordsCard(),
                    const SizedBox(height: 16),
                    // ── Actions SOS ─────────────────────────
                    _actionsGrid(),
                    const SizedBox(height: 16),
                    // ── Feedback copié ──────────────────────
                    if (_copiedMsg != null)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.statusGreen.withOpacity(.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.statusGreen.withOpacity(.4)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle, color: AppColors.statusGreen, size: 18),
                          const SizedBox(width: 8),
                          Text(_copiedMsg!, style: const TextStyle(color: AppColors.statusGreen)),
                        ]),
                      ),
                    const SizedBox(height: 16),
                    // ── Appel 112 ───────────────────────────
                    _call112Btn(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _coordsCard() {
    final snap = _snap;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.destructive.withOpacity(.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MA POSITION GPS', style: TextStyle(
            fontFamily: 'Inter', fontSize: 12,
            color: AppColors.textMuted, letterSpacing: 1.5,
          )),
          const SizedBox(height: 12),
          if (snap == null) ...[
            const Center(child: Text('GPS en cours de localisation…',
              style: TextStyle(color: AppColors.mutedForeground))),
          ] else ...[
            _coordRow('Latitude',  '${snap.position.latitude.toStringAsFixed(6)}° N', isMain: true),
            _coordRow('Longitude', '${snap.position.longitude.toStringAsFixed(6)}° E', isMain: true),
            const Divider(height: 20, color: Color(0xFF3A0000)),
            _coordRow('Altitude',  '${snap.altitudeMeters.toStringAsFixed(0)} m'),
            _coordRow('Précision', '±${snap.accuracyMeters.toStringAsFixed(0)} m',
              valueColor: snap.accuracyMeters < 10 ? AppColors.statusGreen : AppColors.statusOrange),
            const Divider(height: 20, color: Color(0xFF3A0000)),
            // Lien maps
            GestureDetector(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: snap.googleMapsUrl));
                _showCopied('Lien Google Maps copié');
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.secondary.withOpacity(.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.map, color: AppColors.secondary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(snap.googleMapsUrl,
                    style: const TextStyle(color: AppColors.secondary, fontSize: 11),
                    overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.copy, color: AppColors.secondary, size: 14),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _coordRow(String label, String value, {bool isMain = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
          Text(value, style: TextStyle(
            fontSize: isMain ? 18 : 14,
            fontWeight: isMain ? FontWeight.w700 : FontWeight.w500,
            color: valueColor ?? (isMain ? const Color(0xFFEF9A9A) : AppColors.onPrimary),
            fontFamily: 'Inter',
          )),
        ],
      ),
    );
  }

  Widget _actionsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: [
        _actionCard(
          icon: Icons.sms,
          label: 'SMS Secours',
          sublabel: 'Message pré-rempli',
          color: AppColors.destructive,
          onTap: () async {
            await _sosService.sendSms(number: '112');
          },
        ),
        _actionCard(
          icon: Icons.content_copy,
          label: 'Copier GPS',
          sublabel: 'Presse-papier',
          color: AppColors.secondary,
          onTap: () async {
            final text = await _sosService.getCoordinatesText();
            if (text != null) {
              await Clipboard.setData(ClipboardData(text: text));
              _showCopied('Coordonnées copiées !');
            }
          },
        ),
        _actionCard(
          icon: Icons.chat,
          label: 'WhatsApp',
          sublabel: 'Partager position',
          color: const Color(0xFF25D166),
          onTap: () => _sosService.shareWhatsApp(),
        ),
        _actionCard(
          icon: Icons.share,
          label: 'Partager',
          sublabel: 'Signal, Mail…',
          color: AppColors.accent,
          onTap: () => _sosService.shareGeneric(),
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(.4)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: color, fontFamily: 'Inter')),
            Text(sublabel, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _call112Btn() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () => _sosService.call112(),
        icon: const Icon(Icons.phone, size: 22),
        label: const Text('APPELER LE 112', style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1, fontFamily: 'Inter')),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.destructive,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 4,
          shadowColor: AppColors.destructive.withOpacity(.5),
        ),
      ),
    );
  }
}
