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

  /// Adresse de la page, position comprise : la 3D s'ouvre là où le rider
  /// regardait, pas sur un point arbitraire.
  static String adresse({
    required double longitude,
    required double latitude,
    required double zoom,
    String fond = 'photo',
  }) =>
      'assets/carte3d/index.html'
      '#lon=${longitude.toStringAsFixed(5)}'
      '&lat=${latitude.toStringAsFixed(5)}'
      '&zoom=${zoom.toStringAsFixed(2)}'
      '&fond=$fond';

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
          onPageFinished: (_) {
            if (mounted) setState(() => _chargement = false);
          },
        ),
      )
      ..loadFlutterAsset(
        Reconnaissance3dScreen.adresse(
          longitude: widget.longitude,
          latitude: widget.latitude,
          zoom: widget.zoom,
          fond: widget.fond,
        ),
      );
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
