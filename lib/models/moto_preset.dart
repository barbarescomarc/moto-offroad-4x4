import 'package:flutter/material.dart';

enum MotoCategory { trail, maxiTrail, enduro }

extension MotoCategoryExt on MotoCategory {
  String get label {
    switch (this) {
      case MotoCategory.trail:     return 'Trail';
      case MotoCategory.maxiTrail: return 'Maxi-Trail';
      case MotoCategory.enduro:    return 'Enduro';
    }
  }

  IconData get icon {
    switch (this) {
      case MotoCategory.trail:     return Icons.two_wheeler;
      case MotoCategory.maxiTrail: return Icons.motorcycle;
      case MotoCategory.enduro:    return Icons.sports_motorsports;
    }
  }
}

class MotoPreset {
  final String name;
  final MotoCategory category;
  final double consumptionL100;
  final double tankLiters;

  const MotoPreset({
    required this.name,
    required this.category,
    required this.consumptionL100,
    required this.tankLiters,
  });
}

const kMotoPresets = <MotoPreset>[
  // ── Trail ────────────────────────────────────────────────
  MotoPreset(name: 'Yamaha Ténéré 700',       category: MotoCategory.trail, consumptionL100: 4.8, tankLiters: 16.0),
  MotoPreset(name: 'KTM 790 Adventure',       category: MotoCategory.trail, consumptionL100: 5.2, tankLiters: 20.0),
  MotoPreset(name: 'BMW F 800 GS',            category: MotoCategory.trail, consumptionL100: 4.8, tankLiters: 16.0),
  MotoPreset(name: 'Honda CB 500 X',          category: MotoCategory.trail, consumptionL100: 4.2, tankLiters: 17.7),
  MotoPreset(name: 'Suzuki V-Strom 650',      category: MotoCategory.trail, consumptionL100: 5.0, tankLiters: 20.0),
  MotoPreset(name: 'Royal Enfield Himalayan', category: MotoCategory.trail, consumptionL100: 4.0, tankLiters: 15.0),

  // ── Maxi-Trail ───────────────────────────────────────────
  MotoPreset(name: 'BMW R 1250 GS',           category: MotoCategory.maxiTrail, consumptionL100: 5.8, tankLiters: 20.0),
  MotoPreset(name: 'Honda Africa Twin 1100',  category: MotoCategory.maxiTrail, consumptionL100: 5.5, tankLiters: 18.8),
  MotoPreset(name: 'KTM 1290 Super Adventure',category: MotoCategory.maxiTrail, consumptionL100: 6.5, tankLiters: 23.0),
  MotoPreset(name: 'Ducati Multistrada V4',   category: MotoCategory.maxiTrail, consumptionL100: 6.2, tankLiters: 22.0),
  MotoPreset(name: 'Triumph Tiger 1200',      category: MotoCategory.maxiTrail, consumptionL100: 6.0, tankLiters: 20.0),
  MotoPreset(name: 'Yamaha Ténéré 1200',      category: MotoCategory.maxiTrail, consumptionL100: 7.0, tankLiters: 23.0),

  // ── Enduro ───────────────────────────────────────────────
  MotoPreset(name: 'KTM EXC 300 (2T)',        category: MotoCategory.enduro, consumptionL100: 1.8, tankLiters: 8.5),
  MotoPreset(name: 'KTM 500 EXC-F',          category: MotoCategory.enduro, consumptionL100: 3.5, tankLiters: 8.5),
  MotoPreset(name: 'Husqvarna TE 300',        category: MotoCategory.enduro, consumptionL100: 1.8, tankLiters: 9.0),
  MotoPreset(name: 'Beta RR 300',             category: MotoCategory.enduro, consumptionL100: 1.9, tankLiters: 9.5),
  MotoPreset(name: 'Sherco 300 SEF-R',        category: MotoCategory.enduro, consumptionL100: 2.0, tankLiters: 9.0),
  MotoPreset(name: 'Gas Gas EC 300',          category: MotoCategory.enduro, consumptionL100: 1.9, tankLiters: 8.0),
];
