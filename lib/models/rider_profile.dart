// ── Types de moto ────────────────────────────────────────────
enum MotoType {
  enduro,       // légère, haute garde au sol
  trail,        // polyvalente route/piste
  adventure,    // maxi-trail (1200cc+)
  cross,        // tout-terrain pur
  quatro,       // 4 roues / SSV
}

extension MotoTypeExt on MotoType {
  String get label {
    switch (this) {
      case MotoType.enduro:    return 'Enduro';
      case MotoType.trail:     return 'Trail / Routière';
      case MotoType.adventure: return 'Adventure (Maxi-trail)';
      case MotoType.cross:     return 'Cross / Tout-terrain';
      case MotoType.quatro:    return 'Quad / SSV';
    }
  }

  // Coefficient de pénalité sur la difficulté
  double get difficultyCoeff {
    switch (this) {
      case MotoType.enduro:    return 0.7;  // plus facile sur pistes
      case MotoType.trail:     return 1.0;
      case MotoType.adventure: return 1.4;  // maxi-trail difficile sur terrain
      case MotoType.cross:     return 0.6;
      case MotoType.quatro:    return 0.9;
    }
  }
}

// ── Types de pneus ───────────────────────────────────────────
enum TyreType {
  road,       // 100% route
  touring,    // 80/20
  enduro,     // 50/50
  offroad,    // 20/80
  extreme,    // 100% offroad
}

extension TyreTypeExt on TyreType {
  String get label {
    switch (this) {
      case TyreType.road:    return 'Route (100% asphalte)';
      case TyreType.touring: return 'Touring (80/20)';
      case TyreType.enduro:  return 'Enduro (50/50)';
      case TyreType.offroad: return 'Offroad (20/80)';
      case TyreType.extreme: return 'Extreme (100% terre)';
    }
  }

  double get gripCoeff {
    switch (this) {
      case TyreType.road:    return 1.6;  // très pénalisant en offroad
      case TyreType.touring: return 1.3;
      case TyreType.enduro:  return 1.0;  // référence
      case TyreType.offroad: return 0.8;
      case TyreType.extreme: return 0.6;
    }
  }
}

// ── Niveau pilote ────────────────────────────────────────────
enum SkillLevel { debutant, confirme, expert }

extension SkillLevelExt on SkillLevel {
  String get label {
    switch (this) {
      case SkillLevel.debutant:  return 'Débutant';
      case SkillLevel.confirme: return 'Confirmé';
      case SkillLevel.expert:   return 'Expert';
    }
  }

  double get skillCoeff {
    switch (this) {
      case SkillLevel.debutant:  return 1.5;  // perçoit plus difficile
      case SkillLevel.confirme: return 1.0;
      case SkillLevel.expert:   return 0.7;
    }
  }

  int get color {
    switch (this) {
      case SkillLevel.debutant:  return 0xFF4CAF50;
      case SkillLevel.confirme: return 0xFFF57C00;
      case SkillLevel.expert:   return 0xFFEF5350;
    }
  }
}

// ── Profil pilote complet ────────────────────────────────────
class RiderProfile {
  final String name;
  final MotoType motoType;
  final TyreType tyreType;
  final SkillLevel skillLevel;
  final double tankLiters;          // capacité réservoir
  final double consumptionL100;     // consommation L/100km
  final int poiRadiusKm;           // rayon POI (5/10/20/50km)

  const RiderProfile({
    this.name = 'Pilote',
    this.motoType = MotoType.trail,
    this.tyreType = TyreType.enduro,
    this.skillLevel = SkillLevel.confirme,
    this.tankLiters = 20.0,
    this.consumptionL100 = 5.0,
    this.poiRadiusKm = 20,
  });

  // ── Autonomie calculée ───────────────────────────────────
  double get rangeKm => (tankLiters / consumptionL100) * 100;

  // ── Difficulté ressentie (base 1-5 → adaptée au profil) ─
  double adjustedDifficulty(double rawDifficulty) {
    return (rawDifficulty * motoType.difficultyCoeff * tyreType.gripCoeff * skillLevel.skillCoeff)
        .clamp(1.0, 5.0);
  }

  RiderProfile copyWith({
    String? name,
    MotoType? motoType,
    TyreType? tyreType,
    SkillLevel? skillLevel,
    double? tankLiters,
    double? consumptionL100,
    int? poiRadiusKm,
  }) {
    return RiderProfile(
      name:           name           ?? this.name,
      motoType:       motoType       ?? this.motoType,
      tyreType:       tyreType       ?? this.tyreType,
      skillLevel:     skillLevel     ?? this.skillLevel,
      tankLiters:     tankLiters     ?? this.tankLiters,
      consumptionL100: consumptionL100 ?? this.consumptionL100,
      poiRadiusKm:    poiRadiusKm    ?? this.poiRadiusKm,
    );
  }
}
