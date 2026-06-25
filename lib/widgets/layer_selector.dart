import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/theme.dart';
import '../providers/map_provider.dart';

class LayerSelectorSheet extends StatelessWidget {
  const LayerSelectorSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final mapProv = context.watch<MapProvider>();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: const Color(0xFF2A2A3E),
              borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 16),
          const Text('FOND DE CARTE', style: TextStyle(
            fontFamily: 'Rajdhani', fontSize: 16, fontWeight: FontWeight.w700,
            color: AppColors.orange, letterSpacing: 1)),
          const SizedBox(height: 12),
          ...MapLayer.values.map((layer) => _layerTile(context, layer, mapProv)),
          const SizedBox(height: 16),
          const Text('OVERLAYS', style: TextStyle(
            fontFamily: 'Rajdhani', fontSize: 12, color: AppColors.textMuted, letterSpacing: 1)),
          const SizedBox(height: 8),
          _overlayTile(context, 'Radar pluie (RainViewer)', Icons.radar,
            mapProv.radarEnabled, mapProv.toggleRadar, AppColors.blue),
          _overlayTile(context, 'Zones impraticables', Icons.warning_outlined,
            mapProv.practicabilityEnabled, mapProv.togglePracticability, AppColors.red),
        ],
      ),
    );
  }

  Widget _layerTile(BuildContext ctx, MapLayer layer, MapProvider prov) {
    final active = prov.activeLayer == layer;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(
        _layerIcon(layer),
        color: active ? AppColors.orange : AppColors.textSecondary,
      ),
      title: Text(layer.label, style: TextStyle(
        color: active ? AppColors.orange : Colors.white,
        fontWeight: active ? FontWeight.w700 : FontWeight.normal,
        fontSize: 14,
      )),
      trailing: active ? const Icon(Icons.check, color: AppColors.orange, size: 18) : null,
      onTap: () {
        prov.setLayer(layer);
        Navigator.pop(ctx);
      },
    );
  }

  Widget _overlayTile(BuildContext ctx, String label, IconData icon,
      bool active, VoidCallback onToggle, Color color) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: active ? color : AppColors.textSecondary),
      title: Text(label, style: TextStyle(
        color: active ? Colors.white : AppColors.textSecondary, fontSize: 13)),
      trailing: Switch(
        value: active,
        onChanged: (_) => onToggle(),
        activeColor: color,
      ),
    );
  }

  IconData _layerIcon(MapLayer l) {
    switch (l) {
      case MapLayer.satellite: return Icons.satellite_alt;
      case MapLayer.osm:       return Icons.forest;
      case MapLayer.ign:       return Icons.terrain;
      case MapLayer.contour:   return Icons.show_chart;
    }
  }
}
