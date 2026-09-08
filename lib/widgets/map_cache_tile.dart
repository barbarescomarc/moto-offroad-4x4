// lib/widgets/map_cache_tile.dart
import 'package:flutter/material.dart';
import '../services/map_tile_cache.dart';

// Section « Application » des réglages : taille du cache de tuiles de
// carte déjà consultées (disponibles hors connexion), et remise à zéro.
class MapCacheTile extends StatefulWidget {
  const MapCacheTile({super.key});

  @override
  State<MapCacheTile> createState() => _MapCacheTileState();
}

class _MapCacheTileState extends State<MapCacheTile> {
  double? _sizeMb;
  int? _tileCount;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await MapTileCache.stats();
    if (!mounted) return;
    setState(() {
      _sizeMb = stats.sizeKb / 1024;
      _tileCount = stats.tileCount;
    });
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    await MapTileCache.clear();
    await _load();
    if (mounted) setState(() => _clearing = false);
  }

  @override
  Widget build(BuildContext context) {
    final hasCache = (_tileCount ?? 0) > 0;
    return ListTile(
      leading: const Icon(Icons.map_outlined),
      title: const Text('Carte hors-ligne'),
      subtitle: Text(
        _sizeMb == null
            ? 'Calcul…'
            : hasCache
                ? '${_sizeMb!.toStringAsFixed(1)} Mo en cache ($_tileCount tuiles) — les zones déjà consultées restent disponibles sans réseau.'
                : 'Aucune tuile en cache pour l\'instant — consulte une zone pour qu\'elle reste disponible hors connexion.',
      ),
      trailing: _clearing
          ? const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(onPressed: hasCache ? _clear : null, child: const Text('Vider')),
    );
  }
}
