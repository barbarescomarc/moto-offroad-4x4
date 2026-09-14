import 'package:flutter/material.dart';

import 'poi.dart';

/// Le véhicule sous le pilote.
///
/// Ce n'est pas une préférence d'affichage : il décide ce que l'application
/// va chercher autour de lui, ce qu'elle lui demande de renseigner, et ce
/// qu'elle a le droit de lui proposer. Un camping-car n'a rien à faire d'un
/// réparateur moto, et un enduro n'a pas de hauteur sous barre à surveiller.
enum VehicleKind { moto, quatreQuatre, van }

extension VehicleKindExt on VehicleKind {
  String get label {
    switch (this) {
      case VehicleKind.moto:         return 'Moto';
      case VehicleKind.quatreQuatre: return '4x4';
      case VehicleKind.van:          return 'Van / Camping-car';
    }
  }

  /// Libellé court, pour les endroits serrés : puces, barres, bandeaux.
  String get shortLabel {
    switch (this) {
      case VehicleKind.moto:         return 'Moto';
      case VehicleKind.quatreQuatre: return '4x4';
      case VehicleKind.van:          return 'Van';
    }
  }

  /// Le véhicule précédé de son article, pour écrire des phrases qui tiennent
  /// debout : « on considère que **le van** est arrêté ». Le genre voyage avec
  /// le véhicule plutôt que d'être recalculé à chaque phrase.
  String get avecArticle {
    switch (this) {
      case VehicleKind.moto:         return 'la moto';
      case VehicleKind.quatreQuatre: return 'le 4x4';
      case VehicleKind.van:          return 'le camping-car';
    }
  }

  /// Accord du participe passé qui suit `avecArticle`.
  String get accordePasse => this == VehicleKind.moto ? 'e' : '';

  IconData get icon {
    switch (this) {
      case VehicleKind.moto:         return Icons.motorcycle;
      case VehicleKind.quatreQuatre: return Icons.directions_car_filled;
      case VehicleKind.van:          return Icons.airport_shuttle;
    }
  }

  /// Ce que l'application cherche autour du véhicule.
  ///
  /// Le carburant est commun aux trois. Le reste ne l'est pas : chercher un
  /// réparateur moto pour un camping-car remplit la carte de points inutiles
  /// et fait payer à Overpass une requête pour rien.
  List<PoiCategory> get poiCategories {
    switch (this) {
      case VehicleKind.moto:
        return const [PoiCategory.gasStation, PoiCategory.motoShop];
      case VehicleKind.quatreQuatre:
        return const [PoiCategory.gasStation, PoiCategory.garage];
      case VehicleKind.van:
        return const [
          PoiCategory.gasStation,
          PoiCategory.aireCampingCar,
          PoiCategory.vidange,
          PoiCategory.eauPotable,
          PoiCategory.borneRecharge,
          PoiCategory.garage,
        ];
    }
  }

  /// Le véhicule a-t-il un gabarit qui l'empêche de passer partout ?
  ///
  /// Un camping-car se fait arrêter par une barre de hauteur, un pont, un
  /// tonnage — obstacles dont la moto se moque. C'est ce qui justifie de
  /// demander hauteur, longueur et poids, et de ne les demander qu'à lui.
  bool get hasGabarit => this == VehicleKind.van;

  /// Le profil de pilotage moto (modèle, pneus, difficulté ressentie)
  /// s'applique-t-il ? Le coefficient de pneus d'un enduro n'a aucun sens
  /// appliqué à un porteur de 3,5 tonnes.
  bool get usesMotoProfile => this == VehicleKind.moto;

  /// Le véhicule a-t-il sa place hors des routes ouvertes ?
  ///
  /// La moto et le 4x4 y vont ; un camping-car n'y a rien à faire, et lui
  /// proposer une piste DFCI serait un mauvais service, pas une liberté.
  bool get roulesHorsRoute => this != VehicleKind.van;

  /// Gabarit par défaut, en mètres et en tonnes : un profilé de 6 m courant.
  /// Sert de point de départ, le pilote corrige avec ses vraies valeurs.
  double get hauteurParDefautM => 2.8;
  double get longueurParDefautM => 6.0;
  double get poidsParDefautT => 3.5;
}

/// L'encombrement du véhicule, tel qu'il faut le dire à un calculateur
/// d'itinéraire pour qu'il évite ce qui ne passe pas.
///
/// Regroupé en un objet plutôt qu'en trois nombres baladeurs : ces valeurs ne
/// voyagent jamais séparément, et en oublier une en chemin — sur un recalcul
/// après déviation, typiquement — revient à envoyer le camping-car sous un
/// pont qu'on savait trop bas.
class GabaritVehicule {
  const GabaritVehicule({
    required this.hauteurM,
    required this.longueurM,
    required this.poidsT,
  });

  final double hauteurM;
  final double longueurM;
  final double poidsT;

  /// Les restrictions au format attendu par OpenRouteService, en mètres et
  /// en tonnes — les unités de l'API, qui sont aussi celles de la carte grise.
  Map<String, double> get restrictionsOrs => {
        'height': hauteurM,
        'length': longueurM,
        'weight': poidsT,
      };

  @override
  bool operator ==(Object other) =>
      other is GabaritVehicule &&
      other.hauteurM == hauteurM &&
      other.longueurM == longueurM &&
      other.poidsT == poidsT;

  @override
  int get hashCode => Object.hash(hauteurM, longueurM, poidsT);

  @override
  String toString() =>
      'GabaritVehicule(${hauteurM}m x ${longueurM}m, ${poidsT}t)';
}
