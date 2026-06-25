import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/theme.dart';
import '../providers/map_provider.dart';

/// Switch Offroad / Route — persistant en haut de la carte
class ModeSwitchWidget extends StatelessWidget {
  const ModeSwitchWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final mapProv = context.watch<MapProvider>();
    final isOffroad = mapProv.isOffroad;

    return GestureDetector(
      onTap: mapProv.toggleNavMode,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgPanel.withOpacity(.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2A2A3E)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tab('Offroad', isOffroad, AppColors.orange),
            _tab('Route',   !isOffroad, AppColors.blue),
          ],
        ),
      ),
    );
  }

  Widget _tab(String label, bool active, Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: active ? Border.all(color: color.withOpacity(.6)) : null,
      ),
      child: Text(label, style: TextStyle(
        fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w400,
        color: active ? color : const Color(0xFF666680),
        fontFamily: 'Rajdhani',
      )),
    );
  }
}
