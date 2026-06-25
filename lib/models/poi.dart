import 'package:latlong2/latlong.dart';

// ── Types de POI ─────────────────────────────────────────────
enum PoiCategory {
  gasStation,
  restaurant,
  hotel,
  camping,
  motoShop,
  bivouac,
  danger,
}

extension PoiCategoryExt on PoiCategory {
  String get label {
    switch (this) {
      case PoiCategory.gasStation: return 'Station service';
      case PoiCategory.restaurant: return 'Restaurant';
      case PoiCategory.hotel:      return 'Hôtel';
      case PoiCategory.camping:    return 'Camping';
      case PoiCategory.motoShop:   return 'Moto / Réparation';
      case PoiCategory.bivouac:    return 'Bivouac';
      case PoiCategory.danger:     return 'Danger';
    }
  }

  String get emoji {
    switch (this) {
      case PoiCategory.gasStation: return '⛽';
      case PoiCategory.restaurant: return '🍽️';
      case PoiCategory.hotel:      return '🏨';
      case PoiCategory.camping:    return '⛺';
      case PoiCategory.motoShop:   return '🔧';
      case PoiCategory.bivouac:    return '🌙';
      case PoiCategory.danger:     return '⚠️';
    }
  }

  int get colorValue {
    switch (this) {
      case PoiCategory.gasStation: return 0xFFE8601C;
      case PoiCategory.restaurant: return 0xFFE91E63;
      case PoiCategory.hotel:      return 0xFF1565C0;
      case PoiCategory.camping:    return 0xFF2E7D32;
      case PoiCategory.motoShop:   return 0xFF6A1B9A;
      case PoiCategory.bivouac:    return 0xFF00695C;
      case PoiCategory.danger:     return 0xFFC62828;
    }
  }
}

// ── Statut légal bivouac ─────────────────────────────────────
enum BivouacLegalStatus { authorized, tolerated, forbidden }

// ── Modèle POI ───────────────────────────────────────────────
class PoiModel {
  final String id;
  final String name;
  final PoiCategory category;
  final LatLng position;
  final String? address;
  final String? phone;
  final String? website;
  final double? distanceFromTrace; // mètres
  final Map<String, dynamic>? extra;

  // Spécifique station service
  final double? fuelPrice;         // €/L
  final bool? hasDiesel;

  // Spécifique bivouac
  final BivouacLegalStatus? bivouacStatus;
  final bool? hasWater;
  final bool? fireAllowed;
  final bool? motoAccessible;

  const PoiModel({
    required this.id,
    required this.name,
    required this.category,
    required this.position,
    this.address,
    this.phone,
    this.website,
    this.distanceFromTrace,
    this.extra,
    this.fuelPrice,
    this.hasDiesel,
    this.bivouacStatus,
    this.hasWater,
    this.fireAllowed,
    this.motoAccessible,
  });

  // Distance en km formatée
  String get distanceLabel {
    if (distanceFromTrace == null) return '';
    final km = distanceFromTrace! / 1000;
    return km < 1 ? '${distanceFromTrace!.toInt()} m' : '${km.toStringAsFixed(1)} km';
  }
}

// ── Alerte carburant ─────────────────────────────────────────
class FuelGapAlert {
  final int startIndex;       // index point trace
  final int endIndex;
  final double gapKm;         // distance de la zone sans station
  final double rangeKm;       // autonomie déclarée
  final LatLng gapCenter;

  const FuelGapAlert({
    required this.startIndex,
    required this.endIndex,
    required this.gapKm,
    required this.rangeKm,
    required this.gapCenter,
  });

  bool get isCritical => gapKm > rangeKm;
}
