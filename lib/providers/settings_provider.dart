import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/moto_preset.dart';
import '../models/rider_profile.dart';
import '../models/vehicle_kind.dart';

class SettingsProvider extends ChangeNotifier {
  static const _kVehicle  = 'vehicle_kind';         // ancien : un index
  static const _kVehiculeNom = 'vehicule_nom';      // le nom, depuis 1.18
  static const _kGarage   = 'garage_vehicules';
  static const _kHauteur  = 'gabarit_hauteur_m';
  static const _kLongueur = 'gabarit_longueur_m';
  static const _kPoids    = 'gabarit_poids_t';
  static const _kVanToutTerrain = 'van_tout_terrain';
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
  static const _kTileDiag    = 'map_tile_diagnostic';
  static const _kAutoReply     = 'call_auto_reply';
  static const _kAutoReplyPos  = 'call_auto_reply_position';
  static const _kAutoReplyAll  = 'call_auto_reply_all';
  static const _kAutoReplyText = 'call_auto_reply_text';
  static const _kPilotEmail          = 'pilot_email';
  static const _kPilotNewsletter     = 'pilot_newsletter_opt_in';
  static const _kFallEnabled         = 'fall_detection_enabled';
  static const _kFallCountdown       = 'fall_countdown_seconds';
  static const _kAlertChannelPhone   = 'alert_channel_phone';
  static const _kAlertChannelServer  = 'alert_channel_server';
  static const _kGuidanceAvoidHighways = 'guidance_avoid_highways';
  static const _kGuidanceAvoidTolls    = 'guidance_avoid_tolls';
  static const _kGuidanceAvoidFerries  = 'guidance_avoid_ferries';
  static const _kGuidancePreferCurvy   = 'guidance_prefer_curvy';
  static const _kGuidanceVoiceMuted    = 'guidance_voice_muted';
  static const _kMapHeadingUp          = 'map_orientation_heading_up';

  // Message envoyé seul, sans que le pilote ait à toucher l'écran.
  static const String defaultAutoReplyMessage = 'Je roule, je ne peux pas répondre';

  // Seuils de pause proposés, en km/h. Un curseur libre autoriserait des
  // valeurs absurdes qui déclencheraient des pauses intempestives.
  static const List<int> pauseSpeedChoices = [2, 5];

  // Silence du GPS au-delà duquel la trace est coupée, en secondes.
  static const List<int> signalGapChoices = [60, 90, 180];

  // Moto par defaut : c'est ce que conduisaient tous les installes avant que
  // le choix existe, et leur reglage ne doit pas changer sous leurs pieds.
  VehicleKind _vehicleKind = VehicleKind.moto;
  // Le garage : ce que le pilote possède, par opposition à ce qu'il conduit
  // aujourd'hui. Les deux étaient confondus tant qu'il n'y avait qu'un seul
  // véhicule — et l'en-tête portait un « mode de navigation » qui disait la
  // même chose dans d'autres mots.
  Set<VehicleKind> _garage = {VehicleKind.moto};
  double _gabaritHauteurM;
  double _gabaritLongueurM;
  double _gabaritPoidsT;
  bool _vanToutTerrain = false;
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
  // Bandeau de diagnostic des tuiles : eteint par defaut. C'est un outil de
  // depannage, pas un element de conduite — il n'a rien a faire sur la carte
  // quand on roule.
  bool _tileDiagnostic   = false;
  bool _autoReplyEnabled        = true;
  bool _autoReplyAttachPosition = true;
  bool _autoReplyAllCallers     = false;
  String _autoReplyMessage      = defaultAutoReplyMessage;
  String _pilotEmail          = '';
  bool   _pilotNewsletterOptIn = false;
  bool   _fallDetectionEnabled = true;
  int    _fallCountdownSeconds = 30;
  bool   _alertChannelPhone    = true;
  bool   _alertChannelServer   = true;
  bool _guidanceAvoidHighways = false;
  bool _guidanceAvoidTolls    = false;
  bool _guidanceAvoidFerries  = false;
  bool _guidancePreferCurvy   = false;
  bool _guidanceVoiceMuted    = false;
  // false = Nord en haut (défaut) ; true = carte tournée selon le cap du
  // rider, comme un GPS auto — utile à l'arrêt comme en roulant.
  bool _mapHeadingUp          = false;

  VehicleKind get vehicleKind      => _vehicleKind;
  Set<VehicleKind> get garage      => Set.unmodifiable(_garage);
  /// Vrai dès qu'il y a un choix à faire : sous cette condition, le
  /// sélecteur de l'en-tête n'a aucune raison d'occuper l'écran.
  bool get plusieursVehicules      => _garage.length > 1;
  double      get gabaritHauteurM  => _gabaritHauteurM;
  double      get gabaritLongueurM => _gabaritLongueurM;
  double      get gabaritPoidsT    => _gabaritPoidsT;

  bool get vanToutTerrain => _vanToutTerrain;

  /// Le véhicule a-t-il le droit de quitter les routes ouvertes ?
  ///
  /// Le camping-car dit non par défaut : envoyer un profilé de 3,5 t sur une
  /// piste DFCI serait un mauvais service. Mais les fourgons 4x4 existent, et
  /// leur refuser la piste reviendrait à décider à leur place — d'où ce
  /// réglage, qui n'a de sens que pour eux. Les autres véhicules y vont déjà
  /// sans avoir à le demander.
  bool get autoriseHorsRoute => _vehicleKind.roulesHorsRoute || _vanToutTerrain;

  /// Le gabarit à transmettre au calcul d'itinéraire, ou `null` quand le
  /// véhicule n'en a pas — une moto passe partout où passe une voiture.
  GabaritVehicule? get gabarit => _vehicleKind.hasGabarit
      ? GabaritVehicule(
          hauteurM:  _gabaritHauteurM,
          longueurM: _gabaritLongueurM,
          poidsT:    _gabaritPoidsT,
        )
      : null;
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
  bool get tileDiagnostic   => _tileDiagnostic;
  bool   get autoReplyEnabled        => _autoReplyEnabled;
  bool   get autoReplyAttachPosition => _autoReplyAttachPosition;
  bool   get autoReplyAllCallers     => _autoReplyAllCallers;
  String get autoReplyMessage        => _autoReplyMessage;
  String get pilotEmail           => _pilotEmail;
  bool   get pilotNewsletterOptIn => _pilotNewsletterOptIn;
  bool   get fallDetectionEnabled => _fallDetectionEnabled;
  int    get fallCountdownSeconds => _fallCountdownSeconds;
  bool   get alertChannelPhone    => _alertChannelPhone;
  bool   get alertChannelServer   => _alertChannelServer;
  bool get guidanceAvoidHighways => _guidanceAvoidHighways;
  bool get guidanceAvoidTolls    => _guidanceAvoidTolls;
  bool get guidanceAvoidFerries  => _guidanceAvoidFerries;
  bool get guidancePreferCurvy   => _guidancePreferCurvy;
  bool get guidanceVoiceMuted    => _guidanceVoiceMuted;
  bool get mapHeadingUp          => _mapHeadingUp;

  SettingsProvider()
      : _gabaritHauteurM  = VehicleKind.van.hauteurParDefautM,
        _gabaritLongueurM = VehicleKind.van.longueurParDefautM,
        _gabaritPoidsT    = VehicleKind.van.poidsParDefautT;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Le véhicule se lisait par son index dans l'énumération. Ajouter la
    // moto de route au milieu aurait donc transformé les 4x4 en motos et
    // les camping-cars en 4x4 : on lit le nom, et l'ancien index ne sert
    // plus qu'une fois, pour les installations d'avant.
    final nomLu = prefs.getString(_kVehiculeNom);
    _vehicleKind = nomLu != null
        ? VehicleKind.values.firstWhere((v) => v.name == nomLu,
            orElse: () => VehicleKind.moto)
        : _vehiculeDepuisAncienIndex(prefs.getInt(_kVehicle));
    // Une installation antérieure au garage n'en a pas : elle possède ce
    // qu'elle conduit, et rien d'autre.
    final garageLu = (prefs.getStringList(_kGarage) ?? const <String>[])
        .map((n) => VehicleKind.values.where((v) => v.name == n))
        .expand((v) => v)
        .toSet();
    _garage = garageLu.isEmpty ? {_vehicleKind} : garageLu;
    if (!_garage.contains(_vehicleKind)) _vehicleKind = _garage.first;
    _gabaritHauteurM  = prefs.getDouble(_kHauteur)  ?? VehicleKind.van.hauteurParDefautM;
    _gabaritLongueurM = prefs.getDouble(_kLongueur) ?? VehicleKind.van.longueurParDefautM;
    _gabaritPoidsT    = prefs.getDouble(_kPoids)    ?? VehicleKind.van.poidsParDefautT;
    _vanToutTerrain   = prefs.getBool(_kVanToutTerrain) ?? false;
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
    _tileDiagnostic   = prefs.getBool(_kTileDiag)   ?? false;
    _autoReplyEnabled        = prefs.getBool(_kAutoReply)    ?? true;
    _autoReplyAttachPosition = prefs.getBool(_kAutoReplyPos) ?? true;
    _autoReplyAllCallers     = prefs.getBool(_kAutoReplyAll) ?? false;
    _autoReplyMessage        = prefs.getString(_kAutoReplyText) ?? defaultAutoReplyMessage;
    _pilotEmail           = prefs.getString(_kPilotEmail) ?? '';
    _pilotNewsletterOptIn = prefs.getBool(_kPilotNewsletter) ?? false;
    _fallDetectionEnabled = prefs.getBool(_kFallEnabled) ?? true;
    _fallCountdownSeconds = (prefs.getInt(_kFallCountdown) ?? 30).clamp(15, 120);
    _alertChannelPhone    = prefs.getBool(_kAlertChannelPhone) ?? true;
    _alertChannelServer   = prefs.getBool(_kAlertChannelServer) ?? true;
    _guidanceAvoidHighways = prefs.getBool(_kGuidanceAvoidHighways) ?? false;
    _guidanceAvoidTolls    = prefs.getBool(_kGuidanceAvoidTolls)    ?? false;
    _guidanceAvoidFerries  = prefs.getBool(_kGuidanceAvoidFerries)  ?? false;
    _guidancePreferCurvy   = prefs.getBool(_kGuidancePreferCurvy)   ?? false;
    _guidanceVoiceMuted    = prefs.getBool(_kGuidanceVoiceMuted)    ?? false;
    _mapHeadingUp          = prefs.getBool(_kMapHeadingUp)          ?? false;
    notifyListeners();
  }

  Future<void> setVehicleKind(VehicleKind kind) async {
    // Conduire un véhicule, c'est le posséder : le sélectionner l'ajoute au
    // garage plutôt que de laisser l'app afficher un gabarit fantôme.
    _vehicleKind = kind;
    _garage.add(kind);
    await _ecrireVehicule();
    notifyListeners();
  }

  /// Ajoute un véhicule au garage sans changer celui qu'on conduit.
  Future<void> ajouterAuGarage(VehicleKind kind) async {
    if (!_garage.add(kind)) return;
    await _ecrireVehicule();
    notifyListeners();
  }

  /// Retire un véhicule du garage. Le dernier ne peut pas partir : sans
  /// véhicule, l'app n'a plus ni profil de routage ni gabarit.
  Future<void> retirerDuGarage(VehicleKind kind) async {
    if (_garage.length <= 1 || !_garage.remove(kind)) return;
    if (_vehicleKind == kind) _vehicleKind = _garage.first;
    await _ecrireVehicule();
    notifyListeners();
  }

  /// Passe au véhicule suivant du garage, dans l'ordre de l'énumération.
  Future<void> vehiculeSuivant() async {
    if (_garage.length <= 1) return;
    final ordonne = VehicleKind.values.where(_garage.contains).toList();
    final i = ordonne.indexOf(_vehicleKind);
    await setVehicleKind(ordonne[(i + 1) % ordonne.length]);
  }

  /// L'ancien enregistrement : 0 = moto, 1 = 4x4, 2 = van, dans l'ordre
  /// de l'énumération d'alors.
  static VehicleKind _vehiculeDepuisAncienIndex(int? index) {
    switch (index) {
      case 1:  return VehicleKind.quatreQuatre;
      case 2:  return VehicleKind.van;
      default: return VehicleKind.moto;
    }
  }

  Future<void> _ecrireVehicule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kVehiculeNom, _vehicleKind.name);
    await prefs.setStringList(
        _kGarage, VehicleKind.values.where(_garage.contains).map((v) => v.name).toList());
  }

  /// Ouvre — ou referme — la piste au camping-car. Voir [autoriseHorsRoute].
  Future<void> setVanToutTerrain(bool autorise) async {
    _vanToutTerrain = autorise;
    (await SharedPreferences.getInstance()).setBool(_kVanToutTerrain, autorise);
    notifyListeners();
  }

  /// Gabarit du camping-car. Les bornes ne sont pas décoratives : au-delà, la
  /// valeur ne décrit plus un véhicule mais une faute de frappe, et une faute
  /// de frappe sur une hauteur sous barre se paie sur la route.
  Future<void> setGabarit({double? hauteurM, double? longueurM, double? poidsT}) async {
    if (hauteurM  != null) _gabaritHauteurM  = hauteurM.clamp(1.5, 4.5);
    if (longueurM != null) _gabaritLongueurM = longueurM.clamp(3.0, 12.0);
    if (poidsT    != null) _gabaritPoidsT    = poidsT.clamp(1.0, 19.0);
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble(_kHauteur,  _gabaritHauteurM);
    prefs.setDouble(_kLongueur, _gabaritLongueurM);
    prefs.setDouble(_kPoids,    _gabaritPoidsT);
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

  Future<void> setTileDiagnostic(bool v) async {
    _tileDiagnostic = v;
    (await SharedPreferences.getInstance()).setBool(_kTileDiag, v);
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

  // ── Réglages de pilotage d'alerte de chute ─────────────
  Future<void> setPilotEmail(String v) async {
    _pilotEmail = v.trim();
    (await SharedPreferences.getInstance()).setString(_kPilotEmail, _pilotEmail);
    notifyListeners();
  }

  Future<void> setPilotNewsletterOptIn(bool v) async {
    _pilotNewsletterOptIn = v;
    (await SharedPreferences.getInstance()).setBool(_kPilotNewsletter, v);
    notifyListeners();
  }

  Future<void> setFallDetectionEnabled(bool v) async {
    _fallDetectionEnabled = v;
    (await SharedPreferences.getInstance()).setBool(_kFallEnabled, v);
    notifyListeners();
  }

  Future<void> setFallCountdownSeconds(int v) async {
    _fallCountdownSeconds = v.clamp(15, 120);
    (await SharedPreferences.getInstance()).setInt(_kFallCountdown, _fallCountdownSeconds);
    notifyListeners();
  }

  Future<void> setAlertChannelPhone(bool v) async {
    _alertChannelPhone = v;
    (await SharedPreferences.getInstance()).setBool(_kAlertChannelPhone, v);
    notifyListeners();
  }

  Future<void> setAlertChannelServer(bool v) async {
    _alertChannelServer = v;
    (await SharedPreferences.getInstance()).setBool(_kAlertChannelServer, v);
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

  Future<void> setGuidancePreferCurvy(bool v) async {
    _guidancePreferCurvy = v;
    (await SharedPreferences.getInstance()).setBool(_kGuidancePreferCurvy, v);
    notifyListeners();
  }

  Future<void> setGuidanceVoiceMuted(bool v) async {
    _guidanceVoiceMuted = v;
    (await SharedPreferences.getInstance()).setBool(_kGuidanceVoiceMuted, v);
    notifyListeners();
  }

  Future<void> toggleMapHeadingUp() async {
    _mapHeadingUp = !_mapHeadingUp;
    (await SharedPreferences.getInstance()).setBool(_kMapHeadingUp, _mapHeadingUp);
    notifyListeners();
  }
}
