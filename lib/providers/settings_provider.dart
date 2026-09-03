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
  static const _kSignalGap   = 'rec_signal_gap';
  static const _kAutoStart   = 'rec_suggest_autostart';
  static const _kMiles       = 'unit_miles';
  static const _kScreenOn    = 'map_keep_screen_on';
  static const _kAutoHideNav = 'map_auto_hide_nav_bar';
  static const _kAutoReply     = 'call_auto_reply';
  static const _kAutoReplyPos  = 'call_auto_reply_position';
  static const _kAutoReplyAll  = 'call_auto_reply_all';
  static const _kAutoReplyText = 'call_auto_reply_text';
  static const _kGuidanceAvoidHighways = 'guidance_avoid_highways';
  static const _kGuidanceAvoidTolls    = 'guidance_avoid_tolls';
  static const _kGuidanceAvoidFerries  = 'guidance_avoid_ferries';
  static const _kGuidanceVoiceMuted    = 'guidance_voice_muted';

  // Message envoyé seul, sans que le pilote ait à toucher l'écran.
  static const String defaultAutoReplyMessage = 'Je roule, je ne peux pas répondre';

  // Seuils de pause proposés, en km/h. Un curseur libre autoriserait des
  // valeurs absurdes qui déclencheraient des pauses intempestives.
  static const List<int> pauseSpeedChoices = [2, 5];

  // Silence du GPS au-delà duquel la trace est coupée, en secondes.
  static const List<int> signalGapChoices = [60, 90, 180];

  SkillLevel _skillLevel  = SkillLevel.confirme;
  MotoPreset? _moto;
  String _riderName       = 'Pilote';
  bool _autoPauseEnabled = true;
  int  _pauseSpeedKmh    = 2;
  int  _signalGapSeconds = 90;
  bool _askNameOnStop    = false;
  bool _suggestAutoStart = false;
  bool _useMiles         = false;
  bool _keepScreenOnMap  = true;
  bool _autoHideNavBar   = true;
  bool _autoReplyEnabled        = true;
  bool _autoReplyAttachPosition = true;
  bool _autoReplyAllCallers     = false;
  String _autoReplyMessage      = defaultAutoReplyMessage;
  bool _guidanceAvoidHighways = false;
  bool _guidanceAvoidTolls    = false;
  bool _guidanceAvoidFerries  = false;
  bool _guidanceVoiceMuted    = false;

  SkillLevel  get skillLevel => _skillLevel;
  MotoPreset? get moto       => _moto;
  String      get riderName  => _riderName;
  bool get autoPauseEnabled => _autoPauseEnabled;
  int  get pauseSpeedKmh    => _pauseSpeedKmh;
  int  get signalGapSeconds => _signalGapSeconds;
  bool get askNameOnStop    => _askNameOnStop;
  bool get suggestAutoStart => _suggestAutoStart;
  bool get useMiles         => _useMiles;
  bool get keepScreenOnMap  => _keepScreenOnMap;
  bool get autoHideNavBar   => _autoHideNavBar;
  bool   get autoReplyEnabled        => _autoReplyEnabled;
  bool   get autoReplyAttachPosition => _autoReplyAttachPosition;
  bool   get autoReplyAllCallers     => _autoReplyAllCallers;
  String get autoReplyMessage        => _autoReplyMessage;
  bool get guidanceAvoidHighways => _guidanceAvoidHighways;
  bool get guidanceAvoidTolls    => _guidanceAvoidTolls;
  bool get guidanceAvoidFerries  => _guidanceAvoidFerries;
  bool get guidanceVoiceMuted    => _guidanceVoiceMuted;

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
    final gap         = prefs.getInt(_kSignalGap)   ?? 90;
    _signalGapSeconds = signalGapChoices.contains(gap) ? gap : 90;
    _askNameOnStop    = prefs.getBool(_kAskName)    ?? false;
    _suggestAutoStart = prefs.getBool(_kAutoStart)  ?? false;
    _useMiles         = prefs.getBool(_kMiles)      ?? false;
    _keepScreenOnMap  = prefs.getBool(_kScreenOn)   ?? true;
    _autoHideNavBar   = prefs.getBool(_kAutoHideNav) ?? true;
    _autoReplyEnabled        = prefs.getBool(_kAutoReply)    ?? true;
    _autoReplyAttachPosition = prefs.getBool(_kAutoReplyPos) ?? true;
    _autoReplyAllCallers     = prefs.getBool(_kAutoReplyAll) ?? false;
    _autoReplyMessage        = prefs.getString(_kAutoReplyText) ?? defaultAutoReplyMessage;
    _guidanceAvoidHighways = prefs.getBool(_kGuidanceAvoidHighways) ?? false;
    _guidanceAvoidTolls    = prefs.getBool(_kGuidanceAvoidTolls)    ?? false;
    _guidanceAvoidFerries  = prefs.getBool(_kGuidanceAvoidFerries)  ?? false;
    _guidanceVoiceMuted    = prefs.getBool(_kGuidanceVoiceMuted)    ?? false;
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

  Future<void> setSignalGapSeconds(int v) async {
    _signalGapSeconds = signalGapChoices.contains(v) ? v : 90;
    (await SharedPreferences.getInstance()).setInt(_kSignalGap, _signalGapSeconds);
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

  Future<void> setAutoHideNavBar(bool v) async {
    _autoHideNavBar = v;
    (await SharedPreferences.getInstance()).setBool(_kAutoHideNav, v);
    notifyListeners();
  }

  // ── Réglages d'auto-réponse aux appels ───────────────────
  Future<void> setAutoReplyEnabled(bool v) async {
    _autoReplyEnabled = v;
    (await SharedPreferences.getInstance()).setBool(_kAutoReply, v);
    notifyListeners();
  }

  Future<void> setAutoReplyAttachPosition(bool v) async {
    _autoReplyAttachPosition = v;
    (await SharedPreferences.getInstance()).setBool(_kAutoReplyPos, v);
    notifyListeners();
  }

  Future<void> setAutoReplyAllCallers(bool v) async {
    _autoReplyAllCallers = v;
    (await SharedPreferences.getInstance()).setBool(_kAutoReplyAll, v);
    notifyListeners();
  }

  Future<void> setAutoReplyMessage(String v) async {
    final cleaned = v.trim();
    _autoReplyMessage = cleaned.isEmpty ? defaultAutoReplyMessage : cleaned;
    (await SharedPreferences.getInstance()).setString(_kAutoReplyText, _autoReplyMessage);
    notifyListeners();
  }

  // ── Réglages de guidage ──────────────────────────────────
  Future<void> setGuidanceAvoidHighways(bool v) async {
    _guidanceAvoidHighways = v;
    (await SharedPreferences.getInstance()).setBool(_kGuidanceAvoidHighways, v);
    notifyListeners();
  }

  Future<void> setGuidanceAvoidTolls(bool v) async {
    _guidanceAvoidTolls = v;
    (await SharedPreferences.getInstance()).setBool(_kGuidanceAvoidTolls, v);
    notifyListeners();
  }

  Future<void> setGuidanceAvoidFerries(bool v) async {
    _guidanceAvoidFerries = v;
    (await SharedPreferences.getInstance()).setBool(_kGuidanceAvoidFerries, v);
    notifyListeners();
  }

  Future<void> setGuidanceVoiceMuted(bool v) async {
    _guidanceVoiceMuted = v;
    (await SharedPreferences.getInstance()).setBool(_kGuidanceVoiceMuted, v);
    notifyListeners();
  }
}
