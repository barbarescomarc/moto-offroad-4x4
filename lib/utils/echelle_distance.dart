// Calcul de l'échelle d'une carte : choix d'un palier « rond » pour la règle
// graduée, et mise en forme des distances. Séparé du widget pour rester
// testable sans carte ni écran.

/// Paliers de la règle graduée, en mètres. Uniquement des valeurs que l'œil
/// lit d'un coup — une règle de « 137 m » ne sert à rien.
const List<double> paliersEchelle = [
  5, 10, 20, 50, 100, 200, 500,
  1000, 2000, 5000, 10000, 20000, 50000,
  100000, 200000, 500000, 1000000,
];

/// Plus grand palier qui tient dans [largeurMaxPixels], à raison de
/// [metresParPixel] mètres par pixel logique.
///
/// Quand même le plus petit palier déborde — carte extrêmement dézoomée sur
/// un petit écran — on renvoie ce plus petit palier : une règle un peu trop
/// longue reste préférable à pas de règle du tout.
double palierPourLargeur({
  required double metresParPixel,
  required double largeurMaxPixels,
}) {
  final metresDisponibles = metresParPixel * largeurMaxPixels;
  return paliersEchelle.lastWhere(
    (palier) => palier <= metresDisponibles,
    orElse: () => paliersEchelle.first,
  );
}

/// Distance en français : mètres entiers en dessous du kilomètre, kilomètres
/// au-delà, avec une décimale tant qu'elle apporte quelque chose.
String formaterDistance(double metres) {
  if (metres < 1000) return '${metres.round()} m';

  final km = metres / 1000;
  if (km >= 10 || km == km.roundToDouble()) return '${km.round()} km';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Arrondi de lecture pour l'équivalence « 1 cm ≈ … » : deux chiffres
/// significatifs suffisent, et annoncer « 237 m » laisserait croire à une
/// précision que l'approximation du centimètre physique n'a pas.
double arrondirPourLecture(double metres) {
  if (metres <= 0) return 0;

  var pas = 1.0;
  while (metres / pas >= 100) {
    pas *= 10;
  }
  while (metres / pas < 10) {
    pas /= 10;
  }
  return (metres / pas).round() * pas;
}
