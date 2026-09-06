import 'package:flutter/material.dart';
import '../app/theme.dart';
import 'speed_limit_badge.dart';

class StatsBar extends StatelessWidget {
  final double speedKmh;
  final double? speedLimitKmh;
  final double? remainingKm;
  final double fuelRangeKm;
  final bool fuelOk;
  final double? altitude;

  const StatsBar({
    super.key,
    required this.speedKmh,
    this.speedLimitKmh,
    this.remainingKm,
    required this.fuelRangeKm,
    required this.fuelOk,
    this.altitude,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.statsBarHeight,
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: Color(0xFF2A2A3E), width: 1)),
      ),
      child: Row(
        children: [
          _speedStat(),
          _divider(),
          if (remainingKm != null) ...[
            _stat('RESTE', '${remainingKm!.toStringAsFixed(1)} km', AppColors.statusGreen),
            _divider(),
          ],
          _stat('CARBU.', '${fuelRangeKm.toStringAsFixed(0)} km',
            fuelOk ? AppColors.statusGreen : AppColors.statusRed),
          if (altitude != null) ...[
            _divider(),
            _stat('ALT.', '${altitude!.toStringAsFixed(0)} m', AppColors.textSecondary),
          ],
        ],
      ),
    );
  }

  Widget _speedStat() {
    final limit = speedLimitKmh;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('VITESSE', style: TextStyle(
            fontSize: 9, color: AppColors.textMuted, letterSpacing: .5)),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${speedKmh.toStringAsFixed(0)} km/h', style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: Colors.white, fontFamily: 'Rajdhani')),
              if (limit != null) ...[
                const SizedBox(width: 6),
                SpeedLimitBadge(limitKmh: limit, size: 24),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(
            fontSize: 9, color: AppColors.textMuted, letterSpacing: .5)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700,
            color: valueColor, fontFamily: 'Rajdhani')),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    width: 1, height: 28,
    color: const Color(0xFF2A2A3E),
  );
}
