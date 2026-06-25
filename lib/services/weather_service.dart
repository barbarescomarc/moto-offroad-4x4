import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/api_keys.dart';

// ── Modèles météo ────────────────────────────────────────────

class HourlyWeather {
  final DateTime time;
  final double temperatureC;
  final double precipitationMm;   // mm de pluie
  final double windSpeedKmh;
  final int weatherCode;          // WMO code

  const HourlyWeather({
    required this.time,
    required this.temperatureC,
    required this.precipitationMm,
    required this.windSpeedKmh,
    required this.weatherCode,
  });

  String get description => _wmoDescription(weatherCode);
  String get icon => _wmoIcon(weatherCode);
  bool get isRaining => precipitationMm > 0.1;
}

class DailyWeather {
  final DateTime date;
  final double maxTempC;
  final double minTempC;
  final double totalPrecipMm;
  final int weatherCode;

  const DailyWeather({
    required this.date,
    required this.maxTempC,
    required this.minTempC,
    required this.totalPrecipMm,
    required this.weatherCode,
  });

  String get icon => _wmoIcon(weatherCode);
}

// ── Score de praticabilité ────────────────────────────────────
class PracticabilityScore {
  final double score;          // 0 (praticable) → 100 (impraticable)
  final double cumul7dMm;      // précipitations 7 derniers jours
  final double forecastMm;     // prévision à l'heure d'arrivée
  final String soilType;       // type de sol estimé
  final double elevationM;     // altitude du point

  const PracticabilityScore({
    required this.score,
    required this.cumul7dMm,
    required this.forecastMm,
    required this.soilType,
    required this.elevationM,
  });

  // Seuils : <30=vert, 30-70=orange, >70=rouge
  bool get isPracticable   => score < 30;
  bool get isDifficult     => score >= 30 && score < 70;
  bool get isImpracticable => score >= 70;

  int get colorValue {
    if (isPracticable)   return 0xFF4CAF50;
    if (isDifficult)     return 0xFFF57C00;
    return 0xFFEF5350;
  }

  String get label {
    if (isPracticable)   return 'Praticable';
    if (isDifficult)     return 'Difficile';
    return 'Impraticable';
  }
}

// ── Radar RainViewer ─────────────────────────────────────────
class RadarFrame {
  final int timestamp;
  final String tileUrl;

  RadarFrame({required this.timestamp, required this.tileUrl});
}

// ── Service météo principal ───────────────────────────────────
class WeatherService {
  static final WeatherService _instance = WeatherService._();
  factory WeatherService() => _instance;
  WeatherService._();

  final _client = http.Client();

  // ── Prévisions 7 jours (horaires + journalières) ─────────
  Future<Map<String, dynamic>?> fetchForecast(LatLng position) async {
    final uri = Uri.parse('${ApiKeys.openMeteoBaseUrl}/forecast').replace(
      queryParameters: {
        'latitude':  position.latitude.toString(),
        'longitude': position.longitude.toString(),
        'hourly':    'temperature_2m,precipitation,wind_speed_10m,weather_code',
        'daily':     'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum',
        'timezone':  'Europe/Paris',
        'forecast_days': '7',
      },
    );

    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Historique 7 jours (précipitations cumulées) ──────────
  Future<double> fetchPrecip7Days(LatLng position) async {
    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 7));

    final uri = Uri.parse('${ApiKeys.openMeteoArchiveUrl}/archive').replace(
      queryParameters: {
        'latitude':   position.latitude.toString(),
        'longitude':  position.longitude.toString(),
        'start_date': _formatDate(startDate),
        'end_date':   _formatDate(now),
        'daily':      'precipitation_sum',
        'timezone':   'Europe/Paris',
      },
    );

    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return 0;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final values = (data['daily']?['precipitation_sum'] as List?)
          ?.whereType<num>()
          .map((v) => v.toDouble())
          .toList() ?? [];
      return values.fold<double>(0.0, (a, b) => a + b);
    } catch (_) {
      return 0;
    }
  }

  // ── Frames radar RainViewer ───────────────────────────────
  Future<List<RadarFrame>> fetchRadarFrames() async {
    try {
      final response = await _client
          .get(Uri.parse(ApiKeys.rainViewerApiUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final radar = data['radar'] as Map<String, dynamic>?;
      final past  = radar?['past'] as List? ?? [];
      final nowcast = radar?['nowcast'] as List? ?? [];

      final all = [...past.takeLast(6), ...nowcast.take(2)];
      return all.map((f) {
        final ts = f['time'] as int;
        return RadarFrame(
          timestamp: ts,
          tileUrl: ApiKeys.rainViewerTileUrl.replaceAll('{timestamp}', ts.toString()),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Calcul du score de praticabilité pour un point GPX ───
  Future<PracticabilityScore> computePracticability({
    required LatLng position,
    required double elevationM,
    required Duration etaFromNow,     // temps estimé avant d'arriver sur ce point
    String soilType = 'mixed',        // 'clay', 'rock', 'sand', 'mixed'
  }) async {
    // Récupération parallèle historique + prévision
    final results = await Future.wait([
      fetchPrecip7Days(position),
      fetchForecast(position),
    ]);

    final cumul7d = results[0] as double;
    final forecast = results[1] as Map<String, dynamic>?;

    // Précipitation prévue à l'heure d'arrivée
    double forecastMm = 0;
    if (forecast != null) {
      final times = (forecast['hourly']?['time'] as List?)?.cast<String>() ?? [];
      final precips = (forecast['hourly']?['precipitation'] as List?)
          ?.map((v) => (v as num?)?.toDouble() ?? 0.0)
          .toList() ?? [];

      final arrivalTime = DateTime.now().add(etaFromNow);
      for (int i = 0; i < times.length; i++) {
        final t = DateTime.tryParse(times[i]);
        if (t != null && t.isAfter(arrivalTime.subtract(const Duration(minutes: 30)))
                      && t.isBefore(arrivalTime.add(const Duration(minutes: 30)))) {
          forecastMm = i < precips.length ? precips[i] : 0;
          break;
        }
      }
    }

    // ── Algorithme de praticabilité ───────────────────────
    // Score = (Cumul7j × CoeffSol × DeniceleCoeff) + (PluiePrevue × 10)
    // Seuils : <30=vert, 30-70=orange, >70=rouge
    final soilCoeff = _soilCoeff(soilType);
    final elevCoeff = elevationM > 1500 ? 1.3 : (elevationM > 800 ? 1.1 : 1.0);

    double score = (cumul7d * soilCoeff * elevCoeff) + (forecastMm * 10);
    score = score.clamp(0, 100);

    return PracticabilityScore(
      score:      score,
      cumul7dMm:  cumul7d,
      forecastMm: forecastMm,
      soilType:   soilType,
      elevationM: elevationM,
    );
  }

  // ── Parsing données horaires ──────────────────────────────
  List<HourlyWeather> parseHourly(Map<String, dynamic> data) {
    final hourly = data['hourly'] as Map<String, dynamic>?;
    if (hourly == null) return [];

    final times    = (hourly['time'] as List?)?.cast<String>() ?? [];
    final temps    = (hourly['temperature_2m'] as List?)?.map((v) => (v as num?)?.toDouble() ?? 0.0).toList() ?? [];
    final precips  = (hourly['precipitation'] as List?)?.map((v) => (v as num?)?.toDouble() ?? 0.0).toList() ?? [];
    final winds    = (hourly['wind_speed_10m'] as List?)?.map((v) => (v as num?)?.toDouble() ?? 0.0).toList() ?? [];
    final codes    = (hourly['weather_code'] as List?)?.map((v) => (v as num?)?.toInt() ?? 0).toList() ?? [];

    final result = <HourlyWeather>[];
    for (int i = 0; i < times.length && i < 48; i++) {
      final t = DateTime.tryParse(times[i]);
      if (t == null) continue;
      result.add(HourlyWeather(
        time:             t,
        temperatureC:     i < temps.length   ? temps[i]   : 0,
        precipitationMm:  i < precips.length ? precips[i] : 0,
        windSpeedKmh:     i < winds.length   ? winds[i]   : 0,
        weatherCode:      i < codes.length   ? codes[i]   : 0,
      ));
    }
    return result;
  }

  // ── Parsing données journalières ─────────────────────────
  List<DailyWeather> parseDaily(Map<String, dynamic> data) {
    final daily = data['daily'] as Map<String, dynamic>?;
    if (daily == null) return [];

    final dates  = (daily['time'] as List?)?.cast<String>() ?? [];
    final maxT   = (daily['temperature_2m_max'] as List?)?.map((v) => (v as num?)?.toDouble() ?? 0.0).toList() ?? [];
    final minT   = (daily['temperature_2m_min'] as List?)?.map((v) => (v as num?)?.toDouble() ?? 0.0).toList() ?? [];
    final precip = (daily['precipitation_sum'] as List?)?.map((v) => (v as num?)?.toDouble() ?? 0.0).toList() ?? [];
    final codes  = (daily['weather_code'] as List?)?.map((v) => (v as num?)?.toInt() ?? 0).toList() ?? [];

    final result = <DailyWeather>[];
    for (int i = 0; i < dates.length; i++) {
      final d = DateTime.tryParse(dates[i]);
      if (d == null) continue;
      result.add(DailyWeather(
        date:           d,
        maxTempC:       i < maxT.length   ? maxT[i]   : 0,
        minTempC:       i < minT.length   ? minT[i]   : 0,
        totalPrecipMm:  i < precip.length ? precip[i] : 0,
        weatherCode:    i < codes.length  ? codes[i]  : 0,
      ));
    }
    return result;
  }

  // ── Coefficients sol ─────────────────────────────────────
  double _soilCoeff(String type) {
    switch (type) {
      case 'clay':  return 2.5;  // argile : très sensible
      case 'sand':  return 1.2;
      case 'rock':  return 0.3;  // rocher : peu affecté
      case 'mixed': return 1.5;
      default:      return 1.5;
    }
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';

  void dispose() => _client.close();
}

// ── Codes WMO → description et icône ─────────────────────────
String _wmoDescription(int code) {
  if (code == 0)              return 'Ciel clair';
  if (code <= 2)              return 'Partiellement nuageux';
  if (code == 3)              return 'Couvert';
  if (code >= 45 && code <= 48) return 'Brouillard';
  if (code >= 51 && code <= 55) return 'Bruine';
  if (code >= 61 && code <= 65) return 'Pluie';
  if (code >= 71 && code <= 75) return 'Neige';
  if (code >= 80 && code <= 82) return 'Averses';
  if (code >= 95)             return 'Orage';
  return 'Nuageux';
}

String _wmoIcon(int code) {
  if (code == 0)              return '☀️';
  if (code <= 2)              return '⛅';
  if (code == 3)              return '☁️';
  if (code >= 45 && code <= 48) return '🌫️';
  if (code >= 51 && code <= 55) return '🌦️';
  if (code >= 61 && code <= 65) return '🌧️';
  if (code >= 71 && code <= 75) return '❄️';
  if (code >= 80 && code <= 82) return '🌦️';
  if (code >= 95)             return '⛈️';
  return '⛅';
}

extension<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
