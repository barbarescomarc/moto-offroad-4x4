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
  // Van / camping-car
  garage,
  aireCampingCar,
  vidange,
  eauPotable,
  borneRecharge,
  // DATAtourisme
  viewpoint,
  guestHouse,
  naturalSite,
  heritage,
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
      case PoiCategory.garage:        return 'Garage / Réparation';
      case PoiCategory.aireCampingCar: return 'Aire camping-car';
      case PoiCategory.vidange:       return 'Vidange eaux usées';
      case PoiCategory.eauPotable:    return 'Eau potable';
      case PoiCategory.borneRecharge: return 'Borne de recharge';
      case PoiCategory.viewpoint:   return 'Point de vue';
      case PoiCategory.guestHouse:  return 'Hébergement';
      case PoiCategory.naturalSite: return 'Site naturel';
      case PoiCategory.heritage:    return 'Patrimoine';
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
      case PoiCategory.garage:        return '🔩';
      case PoiCategory.aireCampingCar: return '🚐';
      case PoiCategory.vidange:       return '🚽';
      case PoiCategory.eauPotable:    return '🚰';
      case PoiCategory.borneRecharge: return '🔌';
      case PoiCategory.viewpoint:   return '🔭';
      case PoiCategory.guestHouse:  return '🛏️';
      case PoiCategory.naturalSite: return '🏞️';
      case PoiCategory.heritage:    return '🏛️';
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
      case PoiCategory.garage:        return 0xFF455A64;
      case PoiCategory.aireCampingCar: return 0xFF0277BD;
      case PoiCategory.vidange:       return 0xFF5D4037;
      case PoiCategory.eauPotable:    return 0xFF0097A7;
      case PoiCategory.borneRecharge: return 0xFF2E7D32;
      case PoiCategory.viewpoint:   return 0xFF00838F;
      case PoiCategory.guestHouse:  return 0xFF8D6E63;
      case PoiCategory.naturalSite: return 0xFF558B2F;
      case PoiCategory.heritage:    return 0xFF6D4C41;
    }
  }

  /// Filtre Overpass correspondant, ou `null` quand la catégorie ne vient pas
  /// d'OpenStreetMap (DATAtourisme, bivouacs saisis à la main, dangers).
  ///
  /// Le sélecteur appartient à la catégorie et non au service qui interroge :
  /// c'est ce qui permet d'ajouter un véhicule, donc un jeu de catégories,
  /// sans rouvrir le code des requêtes.
  String? get overpassSelector {
    switch (this) {
      case PoiCategory.gasStation:    return '[amenity=fuel]';
      case PoiCategory.motoShop:      return '[shop=motorcycle]';
      case PoiCategory.garage:        return '[shop=car_repair]';
      case PoiCategory.aireCampingCar: return '[tourism=caravan_site]';
      case PoiCategory.vidange:       return '[amenity=sanitary_dump_station]';
      case PoiCategory.eauPotable:    return '[amenity=drinking_water]';
      case PoiCategory.borneRecharge: return '[amenity=charging_station]';
      case PoiCategory.camping:       return '[tourism=camp_site]';
      case PoiCategory.restaurant:    return '[amenity=restaurant]';
      case PoiCategory.hotel:         return '[tourism=hotel]';
      case PoiCategory.bivouac:
      case PoiCategory.danger:
      case PoiCategory.viewpoint:
      case PoiCategory.guestHouse:
      case PoiCategory.naturalSite:
      case PoiCategory.heritage:
        return null;
    }
  }
}

/// Retrouve la catégorie d'un élément OpenStreetMap d'après ses tags.
///
/// Rend `null` pour tout ce qu'on n'a pas demandé : Overpass renvoie parfois
/// des éléments en marge de la requête, et un point sans catégorie connue ne
/// doit pas atterrir sur la carte sous une icône choisie au hasard.
PoiCategory? categorieDepuisTags(Map<String, dynamic> tags) {
  const correspondances = <PoiCategory, (String, String)>{
    PoiCategory.gasStation:     ('amenity', 'fuel'),
    PoiCategory.motoShop:       ('shop', 'motorcycle'),
    PoiCategory.garage:         ('shop', 'car_repair'),
    PoiCategory.aireCampingCar: ('tourism', 'caravan_site'),
    PoiCategory.vidange:        ('amenity', 'sanitary_dump_station'),
    PoiCategory.eauPotable:     ('amenity', 'drinking_water'),
    PoiCategory.borneRecharge:  ('amenity', 'charging_station'),
    PoiCategory.camping:        ('tourism', 'camp_site'),
    PoiCategory.restaurant:     ('amenity', 'restaurant'),
    PoiCategory.hotel:          ('tourism', 'hotel'),
  };
  for (final entree in correspondances.entries) {
    final (clef, valeur) = entree.value;
    if (tags[clef] == valeur) return entree.key;
  }
  return null;
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
