import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/theme.dart';
import '../providers/map_provider.dart';

/// Sélecteur de mode de navigation — un badge compact en permanence à
/// l'écran, qui se développe en menu sur un appui long. Changer de mode est
/// une action rare : elle ne mérite pas la place d'un switch à deux
/// segments affiché en continu.
class ModeSwitchWidget extends StatelessWidget {
  const ModeSwitchWidget({super.key});

  static const Map<NavMode, IconData> _icons = {
    NavMode.offroad: Icons.terrain,
    NavMode.route: Icons.route,
    NavMode.fourByFour: Icons.directions_car,
  };

  static const Map<NavMode, Color> _colors = {
    NavMode.offroad: AppColors.orange,
    NavMode.route: AppColors.blue,
    NavMode.fourByFour: AppColors.green,
  };

  @override
  Widget build(BuildContext context) {
    final mapProv = context.watch<MapProvider>();
    final mode = mapProv.navMode;
    final color = _colors[mode]!;

    return GestureDetector(
      onLongPressStart: (details) => _openMenu(context, mapProv, details.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.bgPanel.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .6)),
        ),
        child: Icon(_icons[mode], color: color, size: 18),
      ),
    );
  }

  void _openMenu(BuildContext context, MapProvider mapProv, Offset position) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<NavMode>(
      context: context,
      color: AppColors.bgPanel,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: NavMode.values.map((m) {
        final color = _colors[m]!;
        return PopupMenuItem<NavMode>(
          value: m,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icons[m], color: color, size: 18),
              const SizedBox(width: 10),
              Text(m.label, style: TextStyle(color: color, fontFamily: 'Rajdhani', fontWeight: FontWeight.w700)),
            ],
          ),
        );
      }).toList(),
    ).then((selected) {
      if (selected != null) mapProv.setNavMode(selected);
    });
  }
}
