import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/moto_preset.dart';
import '../models/rider_profile.dart';

class SettingsProvider extends ChangeNotifier {
  static const _kLevel    = 'skill_level';
  static const _kMoto     = 'moto_index';
  static const _kName     = 'rider_name';
  static const _kAutoPause   = 'rec_auto_pause';
  static const _kPauseSpeed  = 'rec_pause_speed';
  static const _kAskName     = 'rec_ask_name';
  static const _kAutoStart   = 'rec_suggest_autostart';
  static const _kMiles       = 'unit_miles';
  static const _kScreenOn    = 'map_keep_screen_on';

  // Seuils de pause proposés, en km/h. Un curseur libre autoriserait des
  // valeurs absurdes qui déclencheraient des pauses intempestives.
  static const List<int> pauseSpeedChoices = [2, 5];

  SkillLevel _skillLevel  = SkillLevel.confirme;
  MotoPreset? _moto;
  String _riderName       = 'Pilote';
  bool _autoPauseEnabled = true;
  int  _pauseSpeedKmh    = 2;
  bool _askNameOnStop    = false;
  bool _suggestAutoStart = false;
  bool _useMiles         = false;
  bool _keepScreenOnMap  = true;

  SkillLevel  get skillLevel => _skillLevel;
  MotoPreset? get moto       => _moto;
  String      get riderName  => _riderName;
  bool get autoPauseEnabled => _autoPauseEnabled;
  int  get pauseSpeedKmh    => _pauseSpeedKmh;
  bool get askNameOnStop    => _askNameOnStop;
  bool get suggestAutoStart => _suggestAutoStart;
  bool get useMiles         => _useMiles;
  bool get keepScreenOnMap  => _keepScreenOnMap;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _skillLevel = SkillLevel.values[
      (prefs.getInt(_kLevel) ?? 1).clamp(0, SkillLevel.values.length - 1)
    ];
    final idx = prefs.getInt(_kMoto);
    _moto      = (idx != null && idx < kMotoPresets.length) ? kMotoPresets[idx] : null;
    _riderName = prefs.getString(_kName) ?? 'Pilote';
    _autoPauseEnabled = prefs.getBool(_kAutoPause)  ?? true;
    final speed       = prefs.getInt(_kPauseSpeed)  ?? 2;
    _pauseSpeedKmh    = pauseSpeedChoices.contains(speed) ? speed : 2;
    _askNameOnStop    = prefs.getBool(_kAskName)    ?? false;
    _suggestAutoStart = prefs.getBool(_kAutoStart)  ?? false;
    _useMiles         = prefs.getBool(_kMiles)      ?? false;
    _keepScreenOnMap  = prefs.getBool(_kScreenOn)   ?? true;
    notifyListeners();
  }

  Future<void> setSkillLevel(SkillLevel level) async {
    _skillLevel = level;
    (await SharedPreferences.getInstance()).setInt(_kLevel, level.index);
    notifyListeners();
  }

  Future<void> selectMoto(MotoPreset m) async {
    _moto = m;
    (await SharedPreferences.getInstance()).setInt(_kMoto, kMotoPresets.indexOf(m));
    notifyListeners();
  }

  Future<void> setRiderName(String name) async {
    _riderName = name.trim().isEmpty ? 'Pilote' : name.trim();
    (await SharedPreferences.getInstance()).setString(_kName, _riderName);
    notifyListeners();
  }

  // ── Réglages d'enregistrement ────────────────────────────
  Future<void> setAutoPauseEnabled(bool v) async {
    _autoPauseEnabled = v;
    (await SharedPreferences.getInstance()).setBool(_kAutoPause, v);
    notifyListeners();
  }

  Future<void> setPauseSpeedKmh(int v) async {
    _pauseSpeedKmh = pauseSpeedChoices.contains(v) ? v : 2;
    (await SharedPreferences.getInstance()).setInt(_kPauseSpeed, _pauseSpeedKmh);
    notifyListeners();
  }

  Future<void> setAskNameOnStop(bool v) async {
    _askNameOnStop = v;
    (await SharedPreferences.getInstance()).setBool(_kAskName, v);
    notifyListeners();
  }

  Future<void> setSuggestAutoStart(bool v) async {
    _suggestAutoStart = v;
    (await SharedPreferences.getInstance()).setBool(_kAutoStart, v);
    notifyListeners();
  }

  Future<void> setUseMiles(bool v) async {
    _useMiles = v;
    (await SharedPreferences.getInstance()).setBool(_kMiles, v);
    notifyListeners();
  }

  Future<void> setKeepScreenOnMap(bool v) async {
    _keepScreenOnMap = v;
    (await SharedPreferences.getInstance()).setBool(_kScreenOn, v);
    notifyListeners();
  }
}
