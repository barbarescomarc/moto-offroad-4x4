import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../providers/map_provider.dart';
import '../../services/weather_service.dart';
import '../../services/location_service.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _weatherService = WeatherService();
  final _locationService = LocationService();

  bool _loading = true;
  String? _error;
  List<HourlyWeather> _hourly = [];
  List<DailyWeather> _daily = [];
  double _precip7d = 0;
  PracticabilityScore? _practicability;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadWeather();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadWeather() async {
    setState(() { _loading = true; _error = null; });

    final snap = _locationService.lastSnapshot
        ?? await _locationService.getCurrentPosition();

    if (snap == null) {
      setState(() { _loading = false; _error = 'GPS non disponible'; });
      return;
    }

    final pos = snap.position;

    try {
      final results = await Future.wait([
        _weatherService.fetchForecast(pos),
        _weatherService.fetchPrecip7Days(pos),
        _weatherService.computePracticability(
          position: pos,
          elevationM: snap.altitudeMeters,
          etaFromNow: Duration.zero,
        ),
      ]);

      final forecast = results[0] as Map<String, dynamic>?;
      final precip7d = results[1] as double;
      final practic  = results[2] as PracticabilityScore;

      if (!mounted) return;
      setState(() {
        _loading = false;
        _precip7d = precip7d;
        _practicability = practic;
        if (forecast != null) {
          _hourly = _weatherService.parseHourly(forecast);
          _daily  = _weatherService.parseDaily(forecast);
        }
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Erreur de chargement météo'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('⛈️  MÉTÉO & PRATICABILITÉ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadWeather,
          ),
          // Toggle radar sur la carte
          Consumer<MapProvider>(
            builder: (ctx, map, _) => IconButton(
              icon: Icon(Icons.radar,
                color: map.radarEnabled ? AppColors.blue : AppColors.textMuted),
              tooltip: 'Radar sur la carte',
              onPressed: map.toggleRadar,
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.orange,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.orange,
          tabs: const [
            Tab(text: 'Praticabilité'),
            Tab(text: '48h'),
            Tab(text: '7 jours'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildPracticabilityTab(),
                    _buildHourlyTab(),
                    _buildDailyTab(),
                  ],
                ),
    );
  }

  // ── Onglet PRATICABILITÉ ──────────────────────────────────
  Widget _buildPracticabilityTab() {
    final p = _practicability;
    if (p == null) return const Center(child: Text('Données indisponibles'));

    final scoreColor = Color(p.colorValue);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Score principal ───────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scoreColor.withOpacity(.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scoreColor.withOpacity(.5)),
            ),
            child: Column(children: [
              Text(p.label, style: TextStyle(
                fontFamily: 'Rajdhani', fontSize: 28, fontWeight: FontWeight.w700,
                color: scoreColor)),
              const SizedBox(height: 8),
              Stack(children: [
                Container(height: 12, decoration: BoxDecoration(
                  color: scoreColor.withOpacity(.15),
                  borderRadius: BorderRadius.circular(6),
                )),
                FractionallySizedBox(
                  widthFactor: (p.score / 100).clamp(0, 1),
                  child: Container(height: 12, decoration: BoxDecoration(
                    color: scoreColor,
                    borderRadius: BorderRadius.circular(6),
                  )),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Score : ${p.score.toStringAsFixed(0)}/100',
                style: TextStyle(color: scoreColor, fontFamily: 'Rajdhani', fontSize: 16)),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Légende couleurs ─────────────────────────
          _colorLegend(),
          const SizedBox(height: 16),

          // ── Détail du calcul ─────────────────────────
          _sectionTitle('DÉTAIL DU CALCUL'),
          const SizedBox(height: 8),
          _detailCard('🌧️ Précipitations 7 derniers jours', '${p.cumul7dMm.toStringAsFixed(1)} mm'),
          _detailCard('🌦️ Pluie prévue à l\'arrivée', '${p.forecastMm.toStringAsFixed(1)} mm/h'),
          _detailCard('🏔️ Altitude', '${p.elevationM.toStringAsFixed(0)} m'),
          _detailCard('🌍 Type de sol', _soilLabel(p.soilType)),
          const SizedBox(height: 16),

          // ── Conseil ──────────────────────────────────
          _adviceCard(p),
          const SizedBox(height: 16),

          // ── Précip. 7 jours ──────────────────────────
          _sectionTitle('PRÉCIPITATIONS 7 DERNIERS JOURS'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A3E)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total cumulé', style: TextStyle(color: AppColors.textSecondary)),
              Text('${_precip7d.toStringAsFixed(1)} mm',
                style: const TextStyle(fontFamily: 'Rajdhani', fontSize: 22,
                  fontWeight: FontWeight.w700, color: AppColors.blue)),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Onglet 48H ────────────────────────────────────────────
  Widget _buildHourlyTab() {
    if (_hourly.isEmpty) return const Center(child: Text('Pas de données', style: TextStyle(color: AppColors.textSecondary)));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _hourly.length,
      itemBuilder: (ctx, i) {
        final h = _hourly[i];
        final isNow = i == 0;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isNow ? AppColors.orange.withOpacity(.08) : AppColors.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isNow ? AppColors.orange.withOpacity(.4) : const Color(0xFF2A2A3E)),
          ),
          child: Row(children: [
            SizedBox(
              width: 46,
              child: Text(
                '${h.time.hour.toString().padLeft(2,'0')}h',
                style: TextStyle(
                  fontFamily: 'Rajdhani', fontSize: 16, fontWeight: FontWeight.w700,
                  color: isNow ? AppColors.orange : AppColors.textSecondary),
              ),
            ),
            Text(h.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(child: Text(h.description,
              style: const TextStyle(color: Colors.white, fontSize: 13))),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${h.temperatureC.toStringAsFixed(0)}°C',
                style: const TextStyle(fontFamily: 'Rajdhani', fontSize: 16,
                  fontWeight: FontWeight.w700, color: Colors.white)),
              if (h.precipitationMm > 0)
                Text('💧 ${h.precipitationMm.toStringAsFixed(1)} mm',
                  style: const TextStyle(fontSize: 11, color: AppColors.blue)),
              if (h.windSpeedKmh > 20)
                Text('💨 ${h.windSpeedKmh.toStringAsFixed(0)} km/h',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ]),
          ]),
        );
      },
    );
  }

  // ── Onglet 7 JOURS ────────────────────────────────────────
  Widget _buildDailyTab() {
    if (_daily.isEmpty) return const Center(child: Text('Pas de données', style: TextStyle(color: AppColors.textSecondary)));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _daily.length,
      itemBuilder: (ctx, i) {
        final d = _daily[i];
        final days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
        final dayLabel = i == 0 ? 'Aujourd\'hui' : days[(d.date.weekday - 1) % 7];

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A3E)),
          ),
          child: Row(children: [
            SizedBox(
              width: 90,
              child: Text(dayLabel, style: TextStyle(
                fontFamily: 'Rajdhani', fontSize: 15, fontWeight: FontWeight.w600,
                color: i == 0 ? AppColors.orange : Colors.white)),
            ),
            Text(d.icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('${d.maxTempC.toStringAsFixed(0)}°',
                  style: const TextStyle(fontFamily: 'Rajdhani', fontSize: 18,
                    fontWeight: FontWeight.w700, color: Colors.white)),
                Text(' / ${d.minTempC.toStringAsFixed(0)}°',
                  style: const TextStyle(fontFamily: 'Rajdhani', fontSize: 14,
                    color: AppColors.textSecondary)),
              ]),
              if (d.totalPrecipMm > 0)
                Text('💧 ${d.totalPrecipMm.toStringAsFixed(1)} mm',
                  style: const TextStyle(fontSize: 11, color: AppColors.blue)),
            ])),
            // Mini indicateur praticabilité
            _miniPracticBar(d.totalPrecipMm),
          ]),
        );
      },
    );
  }

  // ── Widgets utilitaires ───────────────────────────────────
  Widget _colorLegend() {
    return Row(children: [
      _legendDot(AppColors.statusGreen, 'Praticable (<30)'),
      const SizedBox(width: 12),
      _legendDot(AppColors.statusOrange, 'Difficile (30-70)'),
      const SizedBox(width: 12),
      _legendDot(AppColors.statusRed, 'Impraticable (>70)'),
    ]);
  }

  Widget _legendDot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
    ],
  );

  Widget _detailCard(String label, String value) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFF2A2A3E)),
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
    ]),
  );

  Widget _adviceCard(PracticabilityScore p) {
    final String advice;
    final Color color;
    if (p.isPracticable) {
      advice = 'Les conditions sont bonnes. La piste est praticable dans l\'état actuel.';
      color = AppColors.statusGreen;
    } else if (p.isDifficult) {
      advice = 'Conditions dégradées. Pneus enduro recommandés. Prudence sur les passages argileux.';
      color = AppColors.statusOrange;
    } else {
      advice = 'Piste déconseillée. Risque de glissades et d\'embourbement. Attendre au moins 48h de sec.';
      color = AppColors.statusRed;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(p.isPracticable ? Icons.check_circle : Icons.warning_amber,
          color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(advice,
          style: TextStyle(color: color, fontSize: 13, height: 1.4))),
      ]),
    );
  }

  Widget _miniPracticBar(double precipMm) {
    final score = (precipMm * 3).clamp(0, 100);
    final color = score < 30
        ? AppColors.statusGreen
        : score < 70 ? AppColors.statusOrange : AppColors.statusRed;
    return Container(
      width: 6, height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3E),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: (score / 100),
          child: Container(decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(3))),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t, style: const TextStyle(
    fontFamily: 'Rajdhani', fontSize: 12, color: AppColors.textMuted, letterSpacing: 1.5));

  Widget _buildError() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.cloud_off, color: AppColors.textMuted, size: 48),
      const SizedBox(height: 12),
      Text(_error ?? 'Erreur', style: const TextStyle(color: AppColors.textSecondary)),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: _loadWeather, child: const Text('Réessayer')),
    ],
  ));

  String _soilLabel(String type) {
    switch (type) {
      case 'clay':  return 'Argileux (sensible)';
      case 'rock':  return 'Rocheux (résistant)';
      case 'sand':  return 'Sableux';
      default:      return 'Mixte';
    }
  }
}
