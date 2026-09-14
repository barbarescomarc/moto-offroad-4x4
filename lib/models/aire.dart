import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// Les services d'une aire, tels que quelqu'un les a renseignés.
///
/// Chaque service vaut `true`, `false`, ou reste absent — et absent ne veut
/// pas dire non : il veut dire que personne ne l'a renseigné. Confondre les
/// deux ferait afficher « pas de vidange » sur une aire qui en a une.
class AireServices {
  const AireServices(this._valeurs);

  factory AireServices.depuisJson(Map<String, dynamic>? json) {
    if (json == null) return const AireServices({});
    final valeurs = <String, bool>{};
    for (final entree in json.entries) {
      if (entree.value is bool) valeurs[entree.key] = entree.value as bool;
    }
    return AireServices(valeurs);
  }

  final Map<String, bool> _valeurs;

  static const Map<String, String> libelles = {
    'eau': 'Eau potable',
    'vidange': 'Vidange',
    'electricite': 'Électricité',
    'wc': 'WC',
    'douche': 'Douche',
    'wifi': 'Wi-Fi',
  };

  bool get estVide => _valeurs.isEmpty;
  bool? operator [](String service) => _valeurs[service];
  Iterable<String> get renseignes => _valeurs.keys;

  /// Seulement ceux qui sont présents : une fiche liste ce qu'on trouve sur
  /// place, pas l'inventaire de ce qui manque.
  List<String> get presents =>
      _valeurs.entries.where((e) => e.value).map((e) => e.key).toList();

  Map<String, bool> toJson() => Map.unmodifiable(_valeurs);
}

/// Une aire de camping-car, telle que le serveur la connaît.
///
/// Presque tous les champs sont facultatifs, et ce n'est pas un défaut de
/// conception : dans OpenStreetMap le prix n'est renseigné que sur 12 % des
/// aires, le nombre de places sur 22 %, la hauteur limite sur moins de 1,5 %.
/// La fiche doit donc savoir dire « non renseigné » proprement, et proposer
/// de compléter — c'est ce vide qui fait la base.
class AireModel {
  const AireModel({
    required this.id,
    required this.position,
    required this.source,
    this.name,
    this.description,
    this.services = const AireServices({}),
    this.priceText,
    this.priceEur,
    this.capacity,
    this.maxHeightM,
    this.maxLengthM,
    this.openingHours,
    this.phone,
    this.website,
    this.updatedAt,
  });

  factory AireModel.depuisJson(Map<String, dynamic> json) => AireModel(
        id: json['id'] as String,
        position: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lng'] as num).toDouble(),
        ),
        source: json['source'] as String? ?? 'osm',
        name: json['name'] as String?,
        description: json['description'] as String?,
        services: AireServices.depuisJson(json['services'] as Map<String, dynamic>?),
        priceText: json['priceText'] as String?,
        priceEur: (json['priceEur'] as num?)?.toDouble(),
        capacity: (json['capacity'] as num?)?.toInt(),
        maxHeightM: (json['maxHeightM'] as num?)?.toDouble(),
        maxLengthM: (json['maxLengthM'] as num?)?.toDouble(),
        openingHours: json['openingHours'] as String?,
        phone: json['phone'] as String?,
        website: json['website'] as String?,
        updatedAt: (json['updatedAt'] as num?)?.toInt(),
      );

  final String id;
  final LatLng position;
  final String source;
  final String? name;
  final String? description;
  final AireServices services;
  final String? priceText;
  final double? priceEur;
  final int? capacity;
  final double? maxHeightM;
  final double? maxLengthM;
  final String? openingHours;
  final String? phone;
  final String? website;
  final int? updatedAt;

  /// Une aire sans nom en a quand même un à afficher : un libellé vide
  /// laisserait une fiche sans titre.
  String get nomAffiche => (name == null || name!.trim().isEmpty) ? 'Aire sans nom' : name!;

  /// Le camping-car passe-t-il ? `null` quand la hauteur n'est pas connue —
  /// et une hauteur inconnue n'est pas un feu vert.
  bool? passeAvecHauteur(double hauteurM) =>
      maxHeightM == null ? null : hauteurM <= maxHeightM!;

  Map<String, Object?> versLigneSqlite() => {
        'id': id,
        'lat': position.latitude,
        'lng': position.longitude,
        'source': source,
        'name': name,
        'description': description,
        'services_json': services.estVide ? null : jsonEncode(services.toJson()),
        'price_text': priceText,
        'price_eur': priceEur,
        'capacity': capacity,
        'max_height_m': maxHeightM,
        'max_length_m': maxLengthM,
        'opening_hours': openingHours,
        'phone': phone,
        'website': website,
        'updated_at': updatedAt,
      };

  factory AireModel.depuisLigneSqlite(Map<String, Object?> ligne) => AireModel(
        id: ligne['id'] as String,
        position: LatLng(ligne['lat'] as double, ligne['lng'] as double),
        source: ligne['source'] as String? ?? 'osm',
        name: ligne['name'] as String?,
        description: ligne['description'] as String?,
        services: AireServices.depuisJson(ligne['services_json'] == null
            ? null
            : jsonDecode(ligne['services_json'] as String) as Map<String, dynamic>),
        priceText: ligne['price_text'] as String?,
        priceEur: (ligne['price_eur'] as num?)?.toDouble(),
        capacity: (ligne['capacity'] as num?)?.toInt(),
        maxHeightM: (ligne['max_height_m'] as num?)?.toDouble(),
        maxLengthM: (ligne['max_length_m'] as num?)?.toDouble(),
        openingHours: ligne['opening_hours'] as String?,
        phone: ligne['phone'] as String?,
        website: ligne['website'] as String?,
        updatedAt: (ligne['updated_at'] as num?)?.toInt(),
      );
}

/// Les champs qu'un pilote peut relever, dans l'ordre où la fiche les montre.
///
/// La hauteur d'abord : c'est celui qui n'existe nulle part ailleurs, et
/// celui dont l'absence coûte le plus cher au pied d'un pont.
enum ChampAire { maxHeightM, capacity, priceText, maxLengthM, openingHours }

extension ChampAireExt on ChampAire {
  String get cleServeur {
    switch (this) {
      case ChampAire.maxHeightM:    return 'max_height_m';
      case ChampAire.maxLengthM:    return 'max_length_m';
      case ChampAire.capacity:      return 'capacity';
      case ChampAire.priceText:     return 'price_text';
      case ChampAire.openingHours:  return 'opening_hours';
    }
  }

  String get libelle {
    switch (this) {
      case ChampAire.maxHeightM:   return 'Hauteur limite';
      case ChampAire.maxLengthM:   return 'Longueur limite';
      case ChampAire.capacity:     return 'Nombre de places';
      case ChampAire.priceText:    return 'Tarif';
      case ChampAire.openingHours: return 'Horaires';
    }
  }

  String get unite {
    switch (this) {
      case ChampAire.maxHeightM:
      case ChampAire.maxLengthM:
        return 'm';
      case ChampAire.capacity:
        return 'places';
      case ChampAire.priceText:
      case ChampAire.openingHours:
        return '';
    }
  }

  bool get estNumerique =>
      this == ChampAire.maxHeightM || this == ChampAire.maxLengthM || this == ChampAire.capacity;

  String? valeurAffichee(AireModel aire) {
    switch (this) {
      case ChampAire.maxHeightM:
        return aire.maxHeightM == null ? null : '${aire.maxHeightM} m';
      case ChampAire.maxLengthM:
        return aire.maxLengthM == null ? null : '${aire.maxLengthM} m';
      case ChampAire.capacity:
        return aire.capacity == null ? null : '${aire.capacity} places';
      case ChampAire.priceText:
        return aire.priceText;
      case ChampAire.openingHours:
        return aire.openingHours;
    }
  }
}
