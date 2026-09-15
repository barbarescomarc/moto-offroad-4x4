import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../utils/echelle_distance.dart';
import '../app/theme.dart';

/// Échelle de distance posée sur la carte : une règle graduée, et sous elle
/// ce qu'un centimètre d'écran représente sur le terrain.
///
/// À placer dans les `children` d'un [FlutterMap] : le calcul lit la caméra,
/// donc l'échelle suit le zoom et la latitude sans qu'on ait à la prévenir.
class EchelleCarte extends StatelessWidget {
  const EchelleCarte({super.key, this.margeBas = 8});

  /// Hauteur à réserver sous l'échelle. La carte occupe tout l'écran, y
  /// compris derrière la barre de statistiques : sans cette marge, l'échelle
  /// se retrouverait cachée dessous.
  final double margeBas;

  /// Largeur visée pour la règle, en pixels logiques : assez longue pour se
  /// mesurer à l'œil, assez courte pour ne pas barrer la carte.
  static const double _largeurVisee = 96;

  /// Pixels logiques dans un centimètre d'écran.
  ///
  /// Flutter n'expose pas la densité physique réelle de la dalle, seulement
  /// le pixel logique, défini à 1/160 de pouce sur Android et 1/163 sur iOS.
  /// L'équivalence « 1 cm ≈ … » est donc approchée à quelques pour cent près
  /// — d'où l'arrondi de lecture qui l'accompagne. La règle graduée, elle,
  /// reste exacte : c'est elle qui fait foi pour mesurer une distance.
  static const double _pixelsParCentimetre = 160 / 2.54;

  @override
  Widget build(BuildContext context) {
    final metresParPixel = _metresParPixel(MapCamera.of(context));
    if (metresParPixel <= 0) return const SizedBox.shrink();

    final palier = palierPourLargeur(
      metresParPixel: metresParPixel,
      largeurMaxPixels: _largeurVisee,
    );
    final parCentimetre =
        arrondirPourLecture(metresParPixel * _pixelsParCentimetre);

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.only(left: 12, bottom: margeBas),
        child: IgnorePointer(
          child: _Pastille(
            largeurRegle: palier / metresParPixel,
            legendeRegle: formaterDistance(palier),
            legendeCentimetre: '1 cm ≈ ${formaterDistance(parCentimetre)}',
          ),
        ),
      ),
    );
  }

  /// Mètres couverts par un pixel logique au centre de la carte.
  ///
  /// Mesuré sur le terrain plutôt que déduit du zoom : en projection Web
  /// Mercator un pixel couvre d'autant moins de terrain qu'on monte en
  /// latitude, et l'écart entre Perpignan et Lille est déjà visible.
  double _metresParPixel(MapCamera camera) {
    const reference = 1000.0;
    final centre = camera.center;
    final aLEst = const Distance().offset(centre, reference, 90);
    final pixels =
        (camera.projectAtZoom(aLEst).dx - camera.projectAtZoom(centre).dx).abs();
    return pixels == 0 ? 0 : reference / pixels;
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({
    required this.largeurRegle,
    required this.legendeRegle,
    required this.legendeCentimetre,
  });

  final double largeurRegle;
  final String legendeRegle;
  final String legendeCentimetre;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            legendeRegle,
            style: const TextStyle(
              color: AppColors.foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          CustomPaint(
            size: Size(largeurRegle, 7),
            painter: _ReglePainter(),
          ),
          const SizedBox(height: 3),
          Text(
            legendeCentimetre,
            style: const TextStyle(color: AppColors.mutedForeground, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Une règle en forme de crochet : un trait horizontal fermé à ses deux
/// extrémités, pour que le segment mesuré se voie sans ambiguïté.
class _ReglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final trait = Paint()
      ..color = AppColors.foreground
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square;

    final basGauche = Offset(1, size.height);
    final basDroite = Offset(size.width - 1, size.height);

    canvas.drawLine(basGauche, basDroite, trait);
    canvas.drawLine(basGauche, Offset(basGauche.dx, 0), trait);
    canvas.drawLine(basDroite, Offset(basDroite.dx, 0), trait);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
