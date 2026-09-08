// lib/widgets/offline_download_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import '../app/theme.dart';
import '../services/map_tile_cache.dart';

// Confirmation puis progression du téléchargement d'une zone pour usage
// hors-ligne — vient s'ajouter au cache passif (même magasin de tuiles),
// pas de zone/région gérée séparément.
class OfflineDownloadSheet extends StatefulWidget {
  final DownloadableRegion region;
  final int estimatedTileCount;

  const OfflineDownloadSheet({
    super.key,
    required this.region,
    required this.estimatedTileCount,
  });

  @override
  State<OfflineDownloadSheet> createState() => _OfflineDownloadSheetState();
}

class _OfflineDownloadSheetState extends State<OfflineDownloadSheet> {
  // Estimation grossière : la taille réelle par tuile n'est connue qu'après
  // téléchargement (image satellite vs. fond épuré varient beaucoup).
  static const double _avgTileSizeKb = 20;

  StreamSubscription<DownloadProgress>? _sub;
  DownloadProgress? _progress;
  bool _started = false;
  bool _done = false;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _start() {
    final result = const FMTCStore(MapTileCache.storeName)
        .download
        .startForeground(region: widget.region);
    _sub = result.downloadProgress.listen((p) {
      if (!mounted) return;
      setState(() => _progress = p);
      if (p.percentageProgress >= 100) {
        setState(() => _done = true);
      }
    });
    setState(() => _started = true);
  }

  void _cancel() {
    const FMTCStore(MapTileCache.storeName).download.cancel();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A3E),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 16),
            const Text('TÉLÉCHARGER CETTE ZONE', style: TextStyle(
              fontFamily: 'Rajdhani', fontSize: 16, fontWeight: FontWeight.w700,
              color: AppColors.orange, letterSpacing: 1,
            )),
            const SizedBox(height: 16),
            if (!_started) ..._buildConfirm() else ..._buildProgress(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildConfirm() {
    final sizeMb = widget.estimatedTileCount * _avgTileSizeKb / 1024;
    return [
      Text(
        '~${widget.estimatedTileCount} tuiles — environ ${sizeMb.toStringAsFixed(0)} Mo (estimation approximative).',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
      const SizedBox(height: 4),
      const Text(
        'Vient s\'ajouter au cache déjà disponible hors-ligne.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.download_for_offline_outlined),
          label: const Text('Télécharger'),
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
        ),
      ),
    ];
  }

  List<Widget> _buildProgress() {
    final p = _progress;
    final pct = p == null ? 0.0 : p.percentageProgress / 100;
    return [
      LinearProgressIndicator(
        value: pct.clamp(0, 1),
        backgroundColor: const Color(0xFF2A2A3E),
        color: AppColors.orange,
        minHeight: 8,
        borderRadius: BorderRadius.circular(4),
      ),
      const SizedBox(height: 10),
      Text(
        p == null
            ? 'Préparation…'
            : _done
                ? '${p.successfulTilesCount} tuiles téléchargées.'
                : '${p.attemptedTilesCount} / ${p.maxTilesCount} tuiles — ${p.percentageProgress.toStringAsFixed(0)} %',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: _done
            ? FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Terminé'),
              )
            : OutlinedButton(
                onPressed: _cancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.statusRed,
                  side: const BorderSide(color: AppColors.statusRed),
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text('Annuler'),
              ),
      ),
    ];
  }
}
