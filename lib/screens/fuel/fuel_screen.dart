import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../providers/fuel_provider.dart';
import '../../providers/settings_provider.dart';

class FuelScreen extends StatelessWidget {
  const FuelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fuel     = context.watch<FuelProvider>();
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(title: const Text('⛽  CARBURANT')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Moto sélectionnée ───────────────────────
            _motoBanner(context, settings),
            const SizedBox(height: 16),

            // ── Autonomie actuelle ──────────────────────
            _autonomieCard(fuel),
            const SizedBox(height: 16),

            // ── Consommation rapide ─────────────────────
            _section('CONSOMMATION RAPIDE (L/100 km)'),
            const SizedBox(height: 8),
            _consumptionPresets(context, fuel),
            const SizedBox(height: 16),

            // ── Réglages réservoir ──────────────────────
            _section('RÉGLAGES FINS'),
            const SizedBox(height: 8),
            _slider(context, 'Capacité totale', fuel.tankLiters, 5, 50, 'L',
              (v) => fuel.setTank(v)),
            _slider(context, 'Consommation', fuel.consumptionL100, 1, 20, 'L/100',
              (v) => fuel.setConsumption(v)),
            _slider(context, 'Niveau actuel', fuel.currentFuelL, 0, fuel.tankLiters, 'L',
              (v) => fuel.setCurrentFuel(v)),
            const SizedBox(height: 16),

            // ── Rayon de recherche stations ─────────────
            _section('STATIONS SERVICE — RAYON'),
            const SizedBox(height: 8),
            _radiusSelector(context, fuel),
            const SizedBox(height: 16),

            // ── Bouton "Plein fait" ─────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: fuel.refuel,
                icon: const Icon(Icons.local_gas_station),
                label: const Text('J\'ai fait le plein'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bandeau moto sélectionnée ──────────────────────────────
  Widget _motoBanner(BuildContext context, SettingsProvider settings) {
    final moto = settings.moto;
    return GestureDetector(
      onTap: () => context.go(AppRoutes.settings),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        moto != null
              ? AppColors.orange.withValues(alpha: .08)
              : AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(
            color: moto != null
                ? AppColors.orange.withValues(alpha: .3)
                : const Color(0xFF2A2A3E)),
        ),
        child: Row(
          children: [
            Icon(Icons.motorcycle, color: AppColors.orange, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: moto != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(moto.name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(
                          '${moto.consumptionL100.toStringAsFixed(1)} L/100 · Réservoir ${moto.tankLiters.toStringAsFixed(0)} L',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                    )
                  : const Text('Aucune moto sélectionnée — toucher pour configurer',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Presets consommation ───────────────────────────────────
  Widget _consumptionPresets(BuildContext context, FuelProvider fuel) {
    const presets = <(String, double)>[
      ('2T\n1.8', 1.8),
      ('Enduro\n3.5', 3.5),
      ('Trail\n5.0', 5.0),
      ('GS\n6.0', 6.0),
      ('KTM\n6.5', 6.5),
    ];
    return Row(
      children: presets.map((p) {
        final active = (fuel.consumptionL100 - p.$2).abs() < 0.15;
        return Expanded(
          child: GestureDetector(
            onTap: () => fuel.setConsumption(p.$2),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color:        active ? AppColors.orange.withValues(alpha: .2) : AppColors.bgCard,
                borderRadius: BorderRadius.circular(8),
                border:       Border.all(
                  color: active ? AppColors.orange : const Color(0xFF2A2A3E)),
              ),
              child: Text(
                p.$1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:      active ? AppColors.orange : AppColors.textSecondary,
                  fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  fontFamily: 'Rajdhani',
                  fontSize:   13,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Carte autonomie ────────────────────────────────────────
  Widget _autonomieCard(FuelProvider fuel) {
    final color = fuel.isCritical ? AppColors.statusRed
        : fuel.isLow ? AppColors.statusOrange
        : AppColors.statusGreen;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Autonomie estimée', style: TextStyle(color: AppColors.textSecondary)),
              Text('${fuel.rangeKm.toStringAsFixed(0)} km',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700,
                  color: color, fontFamily: 'Rajdhani')),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fuel.fillPercent,
              backgroundColor: color.withValues(alpha: .15),
              color: color,
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${fuel.currentFuelL.toStringAsFixed(1)} L restants',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              Text('Réservoir : ${fuel.tankLiters.toStringAsFixed(0)} L',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
          if (fuel.isLow) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color:        color.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                Icon(fuel.isCritical ? Icons.error : Icons.warning, color: color, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  fuel.isCritical
                      ? 'Niveau critique — faites le plein dès que possible !'
                      : 'Niveau bas — pensez à vérifier les stations sur la trace',
                  style: TextStyle(color: color, fontSize: 12),
                )),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String title) => Text(title, style: const TextStyle(
    fontFamily: 'Rajdhani', fontSize: 12, color: AppColors.textMuted, letterSpacing: 1.5));

  Widget _slider(BuildContext ctx, String label, double value, double min, double max,
      String unit, ValueChanged<double> onChanged) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            Text('${value.toStringAsFixed(1)} $unit',
              style: const TextStyle(color: Colors.white, fontFamily: 'Rajdhani',
                fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        Slider(
          value:       value.clamp(min, max),
          min:         min,
          max:         max,
          activeColor: AppColors.orange,
          onChanged:   onChanged,
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _radiusSelector(BuildContext ctx, FuelProvider fuel) {
    return Row(
      children: [5, 10, 20, 50].map((km) {
        final active = fuel.searchRadiusKm == km;
        return Expanded(
          child: GestureDetector(
            onTap: () => fuel.setSearchRadius(km),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color:  active ? AppColors.orange.withValues(alpha: .2) : AppColors.bgCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: active ? AppColors.orange : const Color(0xFF2A2A3E)),
              ),
              child: Center(child: Text('$km km',
                style: TextStyle(
                  color:      active ? AppColors.orange : AppColors.textSecondary,
                  fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  fontFamily: 'Rajdhani', fontSize: 14))),
            ),
          ),
        );
      }).toList(),
    );
  }
}
