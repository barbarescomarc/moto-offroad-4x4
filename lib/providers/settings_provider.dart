import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/moto_preset.dart';
import '../models/rider_profile.dart';

class SettingsProvider extends ChangeNotifier {
  static const _kLevel    = 'skill_level';
  static const _kMoto     = 'moto_index';
  static const _kName     = 'rider_name';

  SkillLevel _skillLevel  = SkillLevel.confirme;
  MotoPreset? _moto;
  String _riderName       = 'Pilote';

  SkillLevel  get skillLevel => _skillLevel;
  MotoPreset? get moto       => _moto;
  String      get riderName  => _riderName;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _skillLevel = SkillLevel.values[
      (prefs.getInt(_kLevel) ?? 1).clamp(0, SkillLevel.values.length - 1)
    ];
    final idx = prefs.getInt(_kMoto);
    _moto      = (idx != null && idx < kMotoPresets.length) ? kMotoPresets[idx] : null;
    _riderName = prefs.getString(_kName) ?? 'Pilote';
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
}
