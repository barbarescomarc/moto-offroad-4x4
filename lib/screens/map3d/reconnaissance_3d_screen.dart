import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme.dart';

/// Écran de reconnaissance du terrain en 3D.
///
/// Le relief en volume n'existe que dans la version web de MapLibre : le
/// moteur natif ne l'implémente ni sur iOS ni sur Android (vérifié le
/// 2026-09-12). Cet écran embarque donc une page web, servie depuis les
/// ressources de l'application.
///
/// Il sert à **préparer et observer**, jamais à rouler : l'enregistrement de
/// sortie, le guidage, la détection de chute et le SOS restent entièrement du
/// côté Flutter, sur la carte 2D. Rien d'essentiel ne dépend de cette page.
class Reconnaissance3dScreen extends StatefulWidget {
  const Reconnaissance3dScreen({
    super.key,
    required this.longitude,
    required this.latitude,
    required this.zoom,
    this.fond = 'photo',
  });

  final double longitude;
  final double latitude;
  final double zoom;

  /// `photo` ou `topo` — pour ouvrir sur le même genre de fond que la carte 2D.
  final String fond;

  /// Ressource de la page. `loadFlutterAsset` attend une clé de ressource et
  /// rien d'autre : y accrocher un fragment d'adresse empêche le chargement.
  static const String ressource = 'assets/carte3d/index.html';

  /// Ordre envoyé à la page une fois chargée, pour l'amener là où le rider
  /// regardait — même centre, même échelle, même genre de fond.
  static String ordreDePosition({
    required double longitude,
    required double latitude,
    required double zoom,
    String fond = 'photo',
  }) =>
      'allerA(${longitude.toStringAsFixed(5)}, ${latitude.toStringAsFixed(5)}, '
      '${zoom.toStringAsFixed(2)}, "$fond")';

  @override
  State<Reconnaissance3dScreen> createState() => _Reconnaissance3dScreenState();
}

class _Reconnaissance3dScreenState extends State<Reconnaissance3dScreen> {
  late final WebViewController _controleur;
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    _controleur = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bgPanel)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            // La page construit sa carte de façon asynchrone : on lui laisse
            // le temps d'exposer `allerA` avant de la déplacer.
            for (var essai = 0; essai < 20; essai++) {
              try {
                await _controleur.runJavaScriptReturningResult(
                  Reconnaissance3dScreen.ordreDePosition(
                    longitude: widget.longitude,
                    latitude: widget.latitude,
                    zoom: widget.zoom,
                    fond: widget.fond,
                  ),
                );
                break;
              } catch (_) {
                await Future<void>.delayed(const Duration(milliseconds: 250));
              }
            }
            if (mounted) setState(() => _chargement = false);
          },
          onWebResourceError: (erreur) {
            debugPrint('Reconnaissance 3D : ${erreur.description}');
            if (mounted) setState(() => _chargement = false);
          },
        ),
      )
      ..loadFlutterAsset(Reconnaissance3dScreen.ressource);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPanel,
      appBar: AppBar(
        backgroundColor: AppColors.bgPanel,
        title: const Text('Reconnaissance 3D'),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controleur),
          if (_chargement)
            const Center(child: CircularProgressIndicator(color: AppColors.orange)),
        ],
      ),
    );
  }
}
