import 'package:latlong2/latlong.dart';

// ── Engin utilisé sur la trace partagée ──────────────────────
// `4x4` n'est pas un identifiant Dart valide : le nom d'enum devient
// `quatreQuatre`, seule la valeur `wire` conserve la forme du serveur.
enum TraceVehicle {
  moto('moto', 'Moto'),
  quatreQuatre('4x4', '4x4'),
  mixte('mixte', 'Moto et 4x4');

  const TraceVehicle(this.wire, this.libelle);

  /// Valeur telle qu'échangée avec le serveur.
  final String wire;

  /// Libellé français pour l'affichage.
  final String libelle;

  static TraceVehicle fromWire(String wire) => values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => throw ArgumentError('engin inconnu: $wire'),
      );
}

// ── Difficulté annoncée par l'auteur ─────────────────────────
enum TraceDifficulty {
  facile('facile', 'Facile'),
  moyen('moyen', 'Moyen'),
  difficile('difficile', 'Difficile');

  const TraceDifficulty(this.wire, this.libelle);

  final String wire;
  final String libelle;

  static TraceDifficulty fromWire(String wire) => values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => throw ArgumentError('difficulte inconnue: $wire'),
      );
}

DateTime? _dateFromEpochMs(dynamic valeur) =>
    valeur == null ? null : DateTime.fromMillisecondsSinceEpoch((valeur as num).toInt());

// ── Fiche résumée du catalogue partagé ───────────────────────
// Ce que rendent la liste, la recherche et « mes publications » : assez
// pour afficher une carte de résultat, jamais la description complète.
class SharedTraceSummary {
  final String id;
  final String name;
  final String authorName;
  final TraceVehicle vehicle;
  final TraceDifficulty difficulty;
  final double distanceM;
  final double? elevationGainM;
  final int? durationS;
  final DateTime? recordedAt;
  final DateTime publishedAt;
  final int downloadCount;
  final double startLat;
  final double startLng;
  final double? distanceFromRefM;
  final bool hidden;
  final String? hiddenReason;

  const SharedTraceSummary({
    required this.id,
    required this.name,
    required this.authorName,
    required this.vehicle,
    required this.difficulty,
    required this.distanceM,
    this.elevationGainM,
    this.durationS,
    this.recordedAt,
    required this.publishedAt,
    required this.downloadCount,
    required this.startLat,
    required this.startLng,
    this.distanceFromRefM,
    this.hidden = false,
    this.hiddenReason,
  });

  factory SharedTraceSummary.fromJson(Map<String, dynamic> json) => SharedTraceSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        authorName: json['authorName'] as String,
        vehicle: TraceVehicle.fromWire(json['vehicle'] as String),
        difficulty: TraceDifficulty.fromWire(json['difficulty'] as String),
        distanceM: (json['distanceM'] as num).toDouble(),
        elevationGainM: (json['elevationGainM'] as num?)?.toDouble(),
        durationS: json['durationS'] as int?,
        recordedAt: _dateFromEpochMs(json['recordedAt']),
        publishedAt: _dateFromEpochMs(json['publishedAt'])!,
        downloadCount: json['downloadCount'] as int,
        startLat: (json['startLat'] as num).toDouble(),
        startLng: (json['startLng'] as num).toDouble(),
        distanceFromRefM: (json['distanceFromRefM'] as num?)?.toDouble(),
        hidden: json['hidden'] as bool? ?? false,
        hiddenReason: json['hiddenReason'] as String?,
      );
}

// ── Fiche détaillée d'une trace ──────────────────────────────
// Chargée à l'ouverture de la fiche : ajoute la description complète et un
// aperçu échantillonné du tracé, absents de la liste pour ne pas alourdir
// chaque carte de résultat.
class SharedTraceDetail extends SharedTraceSummary {
  final String description;
  final List<LatLng> preview;

  const SharedTraceDetail({
    required super.id,
    required super.name,
    required super.authorName,
    required super.vehicle,
    required super.difficulty,
    required super.distanceM,
    super.elevationGainM,
    super.durationS,
    super.recordedAt,
    required super.publishedAt,
    required super.downloadCount,
    required super.startLat,
    required super.startLng,
    super.distanceFromRefM,
    super.hidden,
    super.hiddenReason,
    required this.description,
    required this.preview,
  });

  factory SharedTraceDetail.fromJson(Map<String, dynamic> json) => SharedTraceDetail(
        id: json['id'] as String,
        name: json['name'] as String,
        authorName: json['authorName'] as String,
        vehicle: TraceVehicle.fromWire(json['vehicle'] as String),
        difficulty: TraceDifficulty.fromWire(json['difficulty'] as String),
        distanceM: (json['distanceM'] as num).toDouble(),
        elevationGainM: (json['elevationGainM'] as num?)?.toDouble(),
        durationS: json['durationS'] as int?,
        recordedAt: _dateFromEpochMs(json['recordedAt']),
        publishedAt: _dateFromEpochMs(json['publishedAt'])!,
        downloadCount: json['downloadCount'] as int,
        startLat: (json['startLat'] as num).toDouble(),
        startLng: (json['startLng'] as num).toDouble(),
        distanceFromRefM: (json['distanceFromRefM'] as num?)?.toDouble(),
        hidden: json['hidden'] as bool? ?? false,
        hiddenReason: json['hiddenReason'] as String?,
        description: json['description'] as String? ?? '',
        preview: ((json['preview'] as List<dynamic>?) ?? [])
            .map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
            .toList(),
      );
}
