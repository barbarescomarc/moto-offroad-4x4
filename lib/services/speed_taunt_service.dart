// lib/services/speed_taunt_service.dart
import 'package:shared_preferences/shared_preferences.dart';

enum SpeedTaunt { tooFast, tooSlow }

/// Petits messages provocateurs affichés plein écran selon la vitesse —
/// une fois par jour maximum pour chacun, pour ne pas lasser.
class SpeedTauntService {
  SpeedTauntService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;

  static const double fastThresholdKmh = 150;
  static const double slowThresholdKmh = 30;
  static const Duration slowSustainedFor = Duration(minutes: 3);

  static const String _kLastFastDay = 'taunt_last_fast_day';
  static const String _kLastSlowDay = 'taunt_last_slow_day';

  // Début du passage sous le seuil lent en cours, ou null si la vitesse est
  // au-dessus. Remis à zéro dès qu'elle repasse au-dessus — seule une lenteur
  // soutenue compte, pas un simple ralentissement au feu.
  DateTime? _slowSince;

  /// Évalue un relevé de vitesse et renvoie le message à déclencher, le cas
  /// échéant. Ne renvoie jamais deux fois le même message le même jour.
  Future<SpeedTaunt?> onSpeed(double speedKmh) async {
    final now = _clock();

    if (speedKmh < slowThresholdKmh) {
      _slowSince ??= now;
    } else {
      _slowSince = null;
    }

    if (speedKmh > fastThresholdKmh) {
      return await _consumeIfNewDay(_kLastFastDay, now) ? SpeedTaunt.tooFast : null;
    }

    final since = _slowSince;
    if (since != null && now.difference(since) >= slowSustainedFor) {
      return await _consumeIfNewDay(_kLastSlowDay, now) ? SpeedTaunt.tooSlow : null;
    }
    return null;
  }

  Future<bool> _consumeIfNewDay(String key, DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dayKey(now);
    if (prefs.getString(key) == today) return false;
    await prefs.setString(key, today);
    return true;
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
