import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../app/theme.dart';
import '../../app/router.dart';
import '../../providers/map_provider.dart';
import '../../providers/trace_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/fuel_provider.dart';
import '../../providers/solo_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/guidance_provider.dart';
import '../../providers/poi_search_provider.dart';
import '../../providers/fuel_poi_provider.dart';
import '../../models/trace.dart';
import '../../models/favorite_place.dart';
import '../../models/route_result.dart';
import '../../models/poi.dart';
import '../../services/location_service.dart';
import '../../services/routing_service.dart';
import '../../services/ride_repository.dart';
import '../../services/gpx_route_deriver.dart';
import '../../services/map_tile_cache.dart';
import '../../utils/route_geometry.dart';
import '../../services/speed_taunt_service.dart';
import '../../services/tutorial_controller.dart';
import '../../services/tutorial_steps.dart';
import '../../widgets/tutorial_overlay.dart';
import '../../widgets/sos_button.dart';
import '../../widgets/mode_switch.dart';
import '../../widgets/stats_bar.dart';
import '../../widgets/layer_selector.dart';
import '../../widgets/gpx_import_sheet.dart';
import '../../widgets/glass_control.dart';
import '../../widgets/fuel_poi_button.dart';
import '../../utils/map_zoom.dart';
import '../../widgets/map_search_bar.dart';
import '../../widgets/radial_action_menu.dart';
import '../../widgets/recording_panel.dart';
import '../../widgets/guidance_banner.dart';
import '../../widgets/speed_limit_badge.dart';
import '../../widgets/maneuver_tile.dart';
import '../../widgets/poi_search_sheet.dart';
import '../../widgets/offline_download_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final _mapController = MapController();
  final _locationService = LocationService();
  final _tauntService = SpeedTauntService();

  // ── Tutoriel de première ouverture ────────────────────────
  // Clés de ciblage posées sur les widgets réels que le tutoriel met en
  // surbrillance. Toute la logique (étapes, mémorisation, rendu) vit hors
  // de cet écran, voir services/tutorial_controller.dart et
  // widgets/tutorial_overlay.dart.
  final _tutoModeSwitchKey = GlobalKey();
  final _tutoLayersKey = GlobalKey();
  final _tutoActionsKey = GlobalKey();
  final _tutoSosKey = GlobalKey();
  final _tutoRecordingKey = GlobalKey();
  late final _tutorial = TutorialController(
    targets: TutorialTargets(
      modeSwitch: _tutoModeSwitchKey,
      sos: _tutoSosKey,
      recording: _tutoRecordingKey,
      actions: _tutoActionsKey,
      layers: _tutoLayersKey,
    ),
  );

  String? _tauntMessage;
  Timer? _tauntClearTimer;

  // ── Vue 3D inclinée (guidage actif) ───────────────────────
  // Angle et facteur d'échelle réglés à l'oeil pour un rendu proche de
  // TomTom/Waze sans rogner les bords : le zoom compense l'agrandissement
  // apparent dû à l'inclinaison.
  static const double _navTiltPerspective = 0.0018;
  static const double _navTiltAngle = 0.55; // ~31°, en radians
  static const double _navTiltScale = 1.35;

  // ── Zoom automatique à l'approche d'une manœuvre ──────────
  static const double _intersectionZoomThresholdMeters = 150;
  static const double _intersectionZoomBoost = 2.5;
  bool _intersectionZoomActive = false;
  double? _preIntersectionZoom;

  // Décalage gauche du bandeau de guidage quand il partage la pile avec la
  // colonne SOS/enregistrement (paysage et plein écran) : celle-ci commence à
  // 12 et mesure la largeur du halo du bouton SOS. Sans ce décalage elle
  // recouvre l'icône de manœuvre et le début de l'instruction.
  static const double _guidanceBannerLeft =
      12 + AppSizes.sosButtonSize + 12 + 8;

  bool _mapReady = false;

  // ── Trace à main levée ────────────────────────────────────
  static const int _maxDrawPoints = 50;
  bool _isDrawingTrace = false;
  final List<LatLng> _drawPoints = [];
  bool _isComputingDrawnRoute = false;

  // ── Édition de trace ───────────────────────────────────────
  bool _isEditingTrace = false;
  TraceModel? _editingSourceTrace;
  final List<LatLng> _editWaypoints = [];
  List<LatLng>? _editedPolyline;
  bool _isRecomputingEdit = false;

  // Détection du masquage de la barre de navigation : flutter_map émet
  // MapEventSource.dragStart dès le premier micro-mouvement d'un doigt sur
  // la carte, y compris pendant un simple tap. On attend un geste
  // réellement soutenu avant de masquer, pour ne pas la faire disparaître
  // sur un effleurement.
  Timer? _navBarHideTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocation();
    // Après le mur d'inscription, première arrivée sur la carte : le
    // contrôleur ne rouvre le tutoriel que s'il n'a jamais été vu.
    _tutorial.startIfNeeded();
  }

  // Dernier état transmis au système, pour ne pas rappeler le canal natif
  // à chaque reconstruction.
  bool _wakelockOn = false;

  @override
  void dispose() {
    _navBarHideTimer?.cancel();
    _tauntClearTimer?.cancel();
    _tutorial.dispose();
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onMapEvent(MapEvent event, MapProvider mapProv, SettingsProvider settings) {
    if (!settings.autoHideNavBar) return;

    if (event.source == MapEventSource.dragStart) {
      _navBarHideTimer?.cancel();
      _navBarHideTimer = Timer(const Duration(milliseconds: 140), () {
        mapProv.hideNavBar();
      });
    } else if (event.source == MapEventSource.dragEnd) {
      // Le geste s'est terminé avant le délai : c'était un tap, pas un
      // déplacement de la carte — on ne masque pas.
      _navBarHideTimer?.cancel();
    }
  }

  Future<void> _initLocation() async {
    await _locationService.startTracking();
    _locationService.stream.listen((snap) {
      if (!mounted) return;
      final mapProv = context.read<MapProvider>();
      final traceProv = context.read<TraceProvider>();
      final settings = context.read<SettingsProvider>();

      // Centrer la carte sur la position si suivi actif
      if (mapProv.followPosition && _mapReady) {
        _mapController.move(snap.position, _mapController.camera.zoom);
        // Cap en haut : la carte tourne pour garder le sens de circulation
        // vers le haut de l'écran, comme un GPS auto — sinon Nord en haut.
        if (settings.mapHeadingUp) {
          _mapController.rotate(-snap.headingDeg);
        }
      }

      // Mise à jour position sur la trace
      traceProv.updatePosition(snap.position.latitude, snap.position.longitude);

      _checkSpeedTaunt(snap.speedKmh);
      _updateIntersectionZoom(mapProv);
    });
  }

  // ── Zoom automatique à l'approche d'une manœuvre ──────────
  // Rapprocher la carte quand un virage arrive aide à voir l'intersection ;
  // le zoom d'origine (avant l'approche) est restauré une fois la manœuvre
  // passée, pour ne pas imposer un niveau de zoom permanent au rider.
  void _updateIntersectionZoom(MapProvider mapProv) {
    if (!mounted || !_mapReady || !mapProv.followPosition) return;
    final guidance = context.read<GuidanceProvider>();
    final step = guidance.isActive ? guidance.currentStep : null;
    final approaching = step != null &&
        step.maneuver != ManeuverType.straight &&
        guidance.distanceToNextStepMeters <= _intersectionZoomThresholdMeters;

    if (approaching && !_intersectionZoomActive) {
      _intersectionZoomActive = true;
      _preIntersectionZoom = _mapController.camera.zoom;
      _mapController.move(
        _mapController.camera.center,
        (_preIntersectionZoom! + _intersectionZoomBoost).clamp(5, 18),
      );
    } else if (!approaching && _intersectionZoomActive) {
      _intersectionZoomActive = false;
      final restoreZoom = _preIntersectionZoom ?? mapProv.zoom;
      _preIntersectionZoom = null;
      _mapController.move(_mapController.camera.center, restoreZoom);
    }
  }

  void _toggleMapOrientation() {
    final settings = context.read<SettingsProvider>();
    settings.toggleMapHeadingUp();
    if (!settings.mapHeadingUp) {
      // Retour au Nord en haut : on réaligne la carte tout de suite plutôt
      // que d'attendre le prochain relevé GPS.
      _mapController.rotate(0);
    }
  }

  // ── Messages provocateurs selon la vitesse ────────────────
  Future<void> _checkSpeedTaunt(double speedKmh) async {
    final taunt = await _tauntService.onSpeed(speedKmh);
    if (taunt == null || !mounted) return;
    _tauntClearTimer?.cancel();
    setState(() {
      _tauntMessage = switch (taunt) {
        SpeedTaunt.tooFast => 'Crois-tu en Dieu pour aller si vite ?',
        SpeedTaunt.tooSlow => 'Tu te traînes...',
      };
    });
    _tauntClearTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _tauntMessage = null);
    });
  }

  Widget _buildTauntOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: .55),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _tauntMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Écran maintenu allumé uniquement en guidage : carte affichée et suivi
    // de position actif. Ailleurs, l'écran s'éteint normalement.
    final mapProv = context.watch<MapProvider>();
    final settings = context.watch<SettingsProvider>();
    final keepOn = settings.keepScreenOnMap && mapProv.followPosition;
    // build() peut se rejouer très souvent ; on ne franchit le canal natif
    // que lorsque l'état change réellement.
    if (keepOn != _wakelockOn) {
      _wakelockOn = keepOn;
      WakelockPlus.toggle(enable: keepOn);
    }

    // Pas de Stack ici : un Stack dont tous les enfants sont Positioned
    // s'effondre à taille nulle dès que les contraintes ne sont plus tight,
    // ce qu'un Stack englobant (même avec un seul enfant non-Positioned)
    // provoque en aval — la carte entière disparaît alors, boutons compris.
    // Le bandeau de vitesse est ajouté directement dans les Stacks internes
    // de _buildPortrait/_buildLandscape, qui restent tight.
    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;
        return isLandscape ? _buildLandscape() : _buildPortrait();
      },
    );
  }

  // ── PORTRAIT ─────────────────────────────────────────────
  Widget _buildPortrait() {
    final mapProv   = context.watch<MapProvider>();
    final isFullscreen = mapProv.isFullscreen;

    // Pas de Scaffold imbriqué : le Scaffold vient de MainShell
    return ColoredBox(
      color: AppColors.bgDark,
      child: Stack(
        children: [
          // ── Carte plein écran ou non ─────────────────────
          Positioned.fill(child: _buildMap()),

          if (_tauntMessage != null) _buildTauntOverlay(),

          // ── HUD fullscreen ───────────────────────────────
          if (isFullscreen) ...[
            _buildFullscreenHud(),
            _buildSideControls(),
            // Le plein écran est la position de conduite : sans le bandeau,
            // le rider y perdait instruction, alerte de déviation et boutons
            // couper le son / arrêter. Le HUD vitesse/cap et le bouton de
            // sortie sont en bas, le haut est libre.
            _buildGuidanceBanner(),
            _buildFullscreenExitBtn(),
          ] else ...[
            // ── Header ──────────────────────────────────────
            Positioned(top: 0, left: 0, right: 0, child: _buildHeader()),

            // ── Carré (rond) flèche de manœuvre ──────────────
            // Sous l'icône Réglages de l'en-tête plutôt que dans le bandeau
            // du bas : la prochaine manœuvre reste visible même quand
            // l'oeil est déjà en haut de l'écran.
            _buildManeuverTileTop(),

            // ── Bouton SOS (toujours visible) ───────────────
            _buildSideControls(),

            // ── Badge Solo ──────────────────────────────────
            _buildSoloBadge(),

            // ── Bandeau de guidage ────────────────────────────
            // En bas, au-dessus de la barre de stats : la route regardée
            // pendant la conduite est en bas de l'écran, pas en haut.
            _buildGuidanceBannerBottom(),

            // ── Barre de dessin de trace à main levée ────────
            _buildDrawTraceBar(),

            // ── Barre d'édition de trace ──────────────────────
            _buildEditTraceBar(),

            // ── Contrôles carte ──────────────────────────────
            // Recherche d'adresse, Météo et Mode Solo ont rejoint le menu
            // radial de Recentrer (voir _buildMapControls) : appui long
            // dessus pour les atteindre, plutôt qu'une barre de recherche
            // en permanence à l'écran.
            Positioned(
              right: 12,
              bottom: AppSizes.statsBarHeight + 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildMapControls(),
                  const SizedBox(height: 6),
                  // Stations et réparateurs autour du pilote, à la demande :
                  // pensé pour la panne sèche ou mécanique, quand chercher
                  // dans un menu n'est pas une option.
                  FuelPoiButton(
                    // Suivi actif — le cas en roulant — le centre de la carte
                    // EST la position du pilote. S'il a déplacé la carte pour
                    // regarder ailleurs, chercher autour de ce qu'il regarde
                    // est ce qu'il attend.
                    currentCenter: () =>
                        _mapReady ? _mapController.camera.center : mapProv.center,
                    radiusKm: context.read<FuelProvider>().searchRadiusKm,
                    // Reculer pour montrer ce qu'on vient de trouver : au zoom
                    // d'une rue, des stations reparties sur vingt kilometres
                    // sont toutes hors cadre, et le pilote croit que rien ne
                    // s'est passe.
                    onResults: (_) {
                      if (!_mapReady) return;
                      final rayon = context.read<FuelProvider>().searchRadiusKm;
                      _mapController.move(
                        _mapController.camera.center,
                        zoomPourRayonKm(rayon).toDouble(),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  _mapCtrlBtn(
                    Icons.explore,
                    _toggleMapOrientation,
                    active: context.watch<SettingsProvider>().mapHeadingUp,
                  ),
                  const SizedBox(height: 6),
                  // Plein écran : uniquement en portrait, la vue paysage
                  // dédie déjà 35% de l'écran au panneau de statistiques.
                  _mapCtrlBtn(Icons.fullscreen, mapProv.toggleFullscreen),
                ],
              ),
            ),

            // ── Stats bar + fullscreen btn ───────────────────
            Positioned(
              left: 0, right: 0,
              bottom: 0,
              child: Column(children: [
                const RecordingReminder(),
                _buildStatsBar(),
              ]),
            ),
          ],

          // ── Tutoriel de première ouverture ─────────────────
          // Dernier enfant du Stack : au-dessus de tout le reste, quel que
          // soit le mode (fenêtré ou plein écran).
          TutorialOverlay(controller: _tutorial),
        ],
      ),
    );
  }

  // ── PAYSAGE ───────────────────────────────────────────────
  Widget _buildLandscape() {
    // Pas de Scaffold imbriqué : le Scaffold vient de MainShell
    return ColoredBox(
      color: AppColors.bgDark,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 65% gauche = carte
          Expanded(
            flex: 65,
            child: Stack(children: [
              Positioned.fill(child: _buildMap()),
              if (_tauntMessage != null) _buildTauntOverlay(),
              _buildGuidanceBanner(),
              _buildSideControls(),
              _buildSoloBadge(),
              Positioned(
                bottom: 8, right: 8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildMapControls(),
                    const SizedBox(height: 6),
                    _mapCtrlBtn(
                      Icons.explore,
                      _toggleMapOrientation,
                      active: context.watch<SettingsProvider>().mapHeadingUp,
                    ),
                  ],
                ),
              ),

              // ── Tutoriel de première ouverture ─────────────
              // Une rotation en cours de tutoriel rebascule _buildPortrait
              // vers _buildLandscape (OrientationBuilder) : sans cet ajout
              // ici aussi, l'overlay disparaîtrait au lieu de se
              // redisposer, laissant le rider sur une carte vivante sans
              // explication ni moyen de reprendre où il en était.
              TutorialOverlay(controller: _tutorial),
            ]),
          ),
          // 35% droite = panneau stats
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.35,
            child: _buildLandscapePanel(),
          ),
        ],
      ),
    );
  }

  // ── CARTE flutter_map ─────────────────────────────────────
  Widget _buildMap() {
    final mapProv   = context.watch<MapProvider>();
    final traceProv = context.watch<TraceProvider>();
    final groupProv = context.watch<GroupProvider>();
    final settings  = context.watch<SettingsProvider>();
    final guidance  = context.watch<GuidanceProvider>();
    final snap      = _locationService.lastSnapshot;

    final navActive = guidance.isActive;

    final flutterMap = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: mapProv.center,
        initialZoom: mapProv.zoom,
        minZoom: 5,
        maxZoom: 18,
        onMapReady: () => setState(() => _mapReady = true),
        onTap: (_, point) {
          if (_isEditingTrace) {
            _insertEditPoint(point);
            return;
          }
          if (_isDrawingTrace) {
            _addDrawPoint(point);
            return;
          }
          if (mapProv.isFullscreen) mapProv.exitFullscreen();
        },
        onLongPress: (_, point) => _showLongPressSheet(point),
        onMapEvent: (event) => _onMapEvent(event, mapProv, settings),
      ),
      children: [
        // ── Tuile de fond ──────────────────────────────────
        // En guidage actif, le fond choisi par l'utilisateur cède la place à
        // un rendu stylisé/épuré, plus lisible en conduite.
        TileLayer(
          urlTemplate: navActive ? mapProv.navigationTileUrl() : mapProv.activeLayer.tileUrl,
          userAgentPackageName: 'app.motooffroad',
          maxZoom: 18,
          tileProvider: MapTileCache.tileProvider,
        ),

        // ── Labels/frontières du fond de navigation ─────────
        // Le fond Canvas Gray est une photo de fond pure, sans texte : cette
        // surcouche transparente y ajoute noms de lieux et frontières.
        if (navActive)
          TileLayer(
            urlTemplate: mapProv.navigationLabelsOverlayUrl(),
            userAgentPackageName: 'app.motooffroad',
            maxZoom: 18,
            tileProvider: MapTileCache.tileProvider,
          ),

        // ── Noms de rues/lieux sur fond satellite ───────────
        // Masqué en guidage : le fond de navigation porte déjà ses propres
        // labels, la surcouche satellite n'a plus lieu d'être.
        if (!navActive && mapProv.activeLayer.labelsOverlayUrl != null)
          TileLayer(
            urlTemplate: mapProv.activeLayer.labelsOverlayUrl!,
            userAgentPackageName: 'app.motooffroad',
            maxZoom: 18,
            tileProvider: MapTileCache.tileProvider,
          ),

        // ── Overlay radar pluie (RainViewer) ───────────────
        // L'URL est construite dynamiquement (voir MapProvider) : le service
        // ne sert pas de chemin fixe, chaque relevé a son propre identifiant.
        // RainViewer plafonne son propre zoom à 7 (« zoom level not
        // supported » au-delà) : maxNativeZoom réutilise les tuiles de ce
        // niveau en zoomant plus loin sur le fond de carte, au lieu d'en
        // redemander à un niveau que le serveur ne fournit pas.
        if (mapProv.radarEnabled && mapProv.radarTileUrlTemplate != null)
          Opacity(
            opacity: 0.55,
            child: TileLayer(
              urlTemplate: mapProv.radarTileUrlTemplate!,
              userAgentPackageName: 'app.motooffroad',
              maxNativeZoom: 7,
              maxZoom: 18,
            ),
          ),

        // ── Trace GPX ──────────────────────────────────────
        if (traceProv.hasTrace) ...[
          // Portion restante — ruban vif et épais en guidage actif, plus
          // discret en simple suivi de trace hors navigation.
          PolylineLayer(polylines: [
            Polyline(
              points: traceProv.activeTrace!.points
                  .skip(traceProv.currentIndex)
                  .map((p) => p.position)
                  .toList(),
              strokeWidth: navActive ? 6 : 3.5,
              color: navActive ? AppColors.navRoute : AppColors.traceColor,
            ),
          ]),
          // Portion parcourue (vert)
          PolylineLayer(polylines: [
            Polyline(
              points: traceProv.activeTrace!.points
                  .take(traceProv.currentIndex + 1)
                  .map((p) => p.position)
                  .toList(),
              strokeWidth: navActive ? 6 : 3.5,
              color: AppColors.traceDone,
            ),
          ]),
          // Segments impraticables (rouge semi-transparent)
          if (mapProv.practicabilityEnabled)
            PolylineLayer(
              polylines: traceProv.activeTrace!.impracticableSegments
                  .map((seg) => Polyline(
                        points: seg,
                        strokeWidth: 8,
                        color: AppColors.overlayRed,
                      ))
                  .toList(),
            ),
          // Point de départ / arrivée
          MarkerLayer(markers: [
            Marker(
              point: traceProv.activeTrace!.points.first.position,
              width: 20, height: 20,
              child: _traceEndpoint(AppColors.statusGreen),
            ),
            Marker(
              point: traceProv.activeTrace!.points.last.position,
              width: 20, height: 20,
              child: _traceEndpoint(AppColors.orange),
            ),
          ]),
        ],

        // ── Itinéraire de guidage vers une destination ──────
        // Le mode gpxAlert/gpxTurnByTurn affiche déjà la trace suivie
        // ci-dessus ; seul le mode destination (calculé via ORS) a besoin
        // de son propre tracé, absent de route_result tant qu'il n'est pas
        // dessiné explicitement ici.
        if (guidance.mode == GuidanceMode.destination && guidance.route != null) ...[
          PolylineLayer(polylines: [
            Polyline(
              points: guidance.route!.polyline,
              strokeWidth: 6,
              color: AppColors.navRoute,
            ),
          ]),
          MarkerLayer(markers: [
            Marker(
              point: guidance.route!.polyline.last,
              width: 20, height: 20,
              child: _traceEndpoint(AppColors.blue),
            ),
          ]),
        ],

        // ── Point de ralliement groupe ──────────────────────
        if (groupProv.rallyPoint != null)
          MarkerLayer(markers: [
            Marker(
              point: groupProv.rallyPoint!,
              width: 40, height: 40,
              child: _rallyMarker(),
            ),
          ]),

        // ── Membres du groupe ───────────────────────────────
        MarkerLayer(
          markers: groupProv.members
              .where((m) => m.id != groupProv.myMemberId && m.position != null && m.isSharing)
              .where((m) {
                if (m.lastUpdate == null) return true;
                return DateTime.now().difference(m.lastUpdate!) < const Duration(minutes: 2);
              })
              .map((m) => Marker(
                    point: m.position!,
                    width: 36, height: 36,
                    child: _memberMarker(m.name, m.color, _peerOpacity(m.lastUpdate)),
                  ))
              .toList(),
        ),

        // ── Points d'intérêt ────────────────────────────────
        // Deux sources, un seul calque : DATAtourisme pour le tourisme,
        // Overpass pour le carburant et la mécanique. Elles partagent le
        // même modèle, donc le même marqueur et la même fiche.
        MarkerLayer(
          markers: [
            ...context.watch<PoiSearchProvider>().results,
            // Masquees sans etre oubliees : le bouton bascule leur affichage
            // sans rien redemander a Overpass.
            if (context.watch<FuelPoiProvider>().visible)
              ...context.watch<FuelPoiProvider>().results,
          ]
              .map((poi) => Marker(
                    point: poi.position,
                    width: 34, height: 34,
                    child: GestureDetector(
                      onTap: () => _showPoiDetails(poi),
                      child: _poiMarker(poi),
                    ),
                  ))
              .toList(),
        ),

        // ── Trace en cours d'édition ─────────────────────────
        if (_isEditingTrace) ...[
          if (_editedPolyline != null)
            PolylineLayer(polylines: [
              Polyline(points: _editedPolyline!, strokeWidth: 5, color: AppColors.blue),
            ]),
          MarkerLayer(
            markers: [
              for (var i = 0; i < _editWaypoints.length; i++)
                Marker(
                  point: _editWaypoints[i],
                  width: 30, height: 30,
                  child: GestureDetector(
                    onTap: () => _showEditPointMenu(i),
                    child: _editPointMarker(i + 1),
                  ),
                ),
            ],
          ),
        ],

        // ── Trace à main levée en cours de dessin ───────────
        if (_isDrawingTrace && _drawPoints.length >= 2)
          PolylineLayer(polylines: [
            Polyline(points: _drawPoints, strokeWidth: 3, color: AppColors.orange),
          ]),
        if (_isDrawingTrace)
          MarkerLayer(
            markers: [
              for (var i = 0; i < _drawPoints.length; i++)
                Marker(
                  point: _drawPoints[i],
                  width: 26, height: 26,
                  child: _drawPointMarker(i + 1),
                ),
            ],
          ),

        // ── Position du rider ───────────────────────────────
        if (snap != null)
          MarkerLayer(markers: [
            Marker(
              point: snap.position,
              width: 30, height: 30,
              child: _riderMarker(snap.headingDeg),
            ),
          ]),
      ],
    );

    // Vue 3D inclinée façon TomTom, uniquement en guidage + suivi de
    // position actif : ailleurs (consultation libre de la carte), la
    // perspective inclinée gênerait plus qu'elle n'aiderait. Le zoom réel
    // et la rotation heading-up restent gérés par flutter_map ; ce Transform
    // n'est qu'un habillage visuel appliqué par-dessus le rendu fini.
    if (!(navActive && mapProv.followPosition)) return flutterMap;

    return ClipRect(
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, _navTiltPerspective)
          ..rotateX(_navTiltAngle)
          ..scaleByDouble(_navTiltScale, _navTiltScale, _navTiltScale, 1.0),
        child: flutterMap,
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────
  Widget _buildHeader() {
    final traceProv = context.watch<TraceProvider>();
    return _buildHeaderBar(traceProv);
  }

  Widget _buildHeaderBar(TraceProvider traceProv) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 4,
        left: 72, right: 12, bottom: 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.bgDark.withOpacity(.95),
            AppColors.bgDark.withOpacity(.0),
          ],
        ),
      ),
      child: Row(
        children: [
          // Nom de la trace en cours — rien à afficher sinon : le nom de
          // l'appli n'apporte aucune information utile pendant la conduite,
          // il n'occupait que de la place.
          Expanded(
            child: traceProv.hasTrace
                ? Text(
                    traceProv.activeTrace!.name,
                    style: const TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: .8,
                    ),
                    overflow: TextOverflow.ellipsis,
                  )
                : const SizedBox.shrink(),
          ),
          // Switch offroad/route
          KeyedSubtree(key: _tutoModeSwitchKey, child: const ModeSwitchWidget()),
          const SizedBox(width: 4),
          // Import GPX
          _iconBtn(Icons.upload_file, () => _showImportSheet()),
          // Sélecteur de couche
          KeyedSubtree(
            key: _tutoLayersKey,
            child: _iconBtn(Icons.layers_outlined, () => _showLayerSelector()),
          ),
          const SizedBox(width: 4),
          // Réglages
          _iconBtn(Icons.settings_outlined, () => context.go(AppRoutes.settings)),
        ],
      ),
    );
  }

  // ── STATS BAR ─────────────────────────────────────────────
  // Le bouton plein écran a quitté cet emplacement : posé juste au-dessus de
  // la barre de stats sans que sa hauteur soit comptée dans le calcul de
  // position de la colonne de contrôles carte, il finissait chevauché par
  // elle en portrait. Il vit maintenant dans cette même colonne (voir
  // _buildPortrait), qui n'a plus besoin de deviner une hauteur.
  Widget _buildStatsBar() {
    return Consumer4<TraceProvider, FuelProvider, MapProvider, GuidanceProvider>(
      builder: (ctx, trace, fuel, map, guidance, _) {
        final snap = _locationService.lastSnapshot;
        return StatsBar(
          speedKmh:      snap?.speedKmh ?? 0,
          speedLimitKmh: guidance.isActive ? guidance.speedLimitKmh : null,
          remainingKm: trace.hasTrace && snap != null
              ? trace.remainingKm(
                  snap.position.latitude, snap.position.longitude)
              : null,
          fuelRangeKm: fuel.rangeKm,
          fuelOk:      !fuel.isLow,
          altitude:    snap?.altitudeMeters,
        );
      },
    );
  }

  // ── CONTRÔLES CARTE ──────────────────────────────────────
  //
  // Zoom +/- retirés : le pincement à deux doigts fait déjà le travail, et
  // ces deux boutons ne servaient à rien.
  Widget _buildMapControls() {
    final mapProv = context.watch<MapProvider>();
    final traceProv = context.watch<TraceProvider>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Recentrer : appui court inchangé. Appui long puis glissement vers
        // le haut-gauche (côté opposé au bord droit de l'écran et aux
        // boutons Radar/Plein écran juste en dessous) révèle Recherche,
        // Météo et Mode Solo.
        RadialActionMenu(
          key: _tutoActionsKey,
          centerIcon:  mapProv.followPosition ? Icons.my_location : Icons.location_searching,
          centerColor: AppColors.orange,
          centerActive: mapProv.followPosition,
          onCenterTap: () {
            mapProv.toggleFollowPosition();
            final snap = _locationService.lastSnapshot;
            if (snap != null) {
              _mapController.move(snap.position, _mapController.camera.zoom);
            }
          },
          segments: [
            RadialMenuSegment(
              icon: Icons.search, color: AppColors.orange, angleDeg: 190,
              onSelect: _openSearchSheet,
            ),
            RadialMenuSegment(
              icon: Icons.cloud, color: AppColors.blue, angleDeg: 227,
              onSelect: () => context.go(AppRoutes.weather),
            ),
            RadialMenuSegment(
              icon: Icons.shield, color: AppColors.green, angleDeg: 265,
              onSelect: () => context.push(AppRoutes.solo),
            ),
            // Seule entrée vers la liste des favoris : sans elle, un point
            // enregistré depuis l'appui long sur la carte n'était plus
            // atteignable pour lancer un guidage dessus.
            RadialMenuSegment(
              icon: Icons.star, color: AppColors.orange, angleDeg: 302,
              onSelect: _openFavorites,
            ),
            // Seule entrée vers le mode groupe : l'écran (créer/rejoindre,
            // ou gérer un groupe actif) existait déjà côté code mais
            // n'était accessible depuis nulle part dans l'appli.
            RadialMenuSegment(
              icon: Icons.groups, color: AppColors.blue, angleDeg: 339,
              onSelect: () => context.push(AppRoutes.group),
            ),
          ],
        ),
        if (traceProv.hasTrace) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _showGpxGuidanceChooser(traceProv.activeTrace!),
            child: const GlassPuck(icon: Icons.alt_route, color: AppColors.orange),
          ),
        ],
        const SizedBox(height: 6),
        // Radar
        _mapCtrlBtn(
          Icons.radar,
          mapProv.toggleRadar,
          active: mapProv.radarEnabled,
          activeColor: AppColors.blue,
        ),
        const SizedBox(height: 6),
        // Points d'intérêt (DATAtourisme)
        _mapCtrlBtn(
          Icons.travel_explore,
          _openPoiSearchSheet,
          active: context.watch<PoiSearchProvider>().results.isNotEmpty,
          activeColor: AppColors.orange,
        ),
        const SizedBox(height: 6),
        // Trace à main levée
        _mapCtrlBtn(
          Icons.gesture,
          _startDrawingTrace,
          active: _isDrawingTrace,
          activeColor: AppColors.orange,
        ),
        const SizedBox(height: 6),
        // Télécharger la zone visible pour hors-ligne
        _mapCtrlBtn(
          Icons.download_for_offline_outlined,
          _downloadVisibleAreaOffline,
        ),
      ],
    );
  }

  // ── CARTE HORS-LIGNE — zone visible ────────────────────────
  // Se greffe sur le même magasin de tuiles que le cache passif (voir
  // MapTileCache) : pas de zones téléchargées gérées séparément, juste un
  // ajout volontaire au même cache. Plage de zoom relative au zoom actuel
  // (zoom courant à zoom courant + 3) plutôt que fixe : quel que soit le
  // niveau de zoom au moment du tap, le nombre de tuiles reste borné à peu
  // près à la même fourchette (l'écran couvre toujours à peu près le même
  // nombre de tuiles à un zoom donné).
  Future<void> _downloadVisibleAreaOffline() async {
    final mapProv = context.read<MapProvider>();
    final bounds = _mapController.camera.visibleBounds;
    final currentZoom = _mapController.camera.zoom.round().clamp(5, 18);
    final maxZoom = (currentZoom + 3).clamp(5, 18);

    final region = RectangleRegion(bounds).toDownloadable(
      minZoom: currentZoom,
      maxZoom: maxZoom,
      options: TileLayer(
        urlTemplate: mapProv.activeLayer.tileUrl,
        tileProvider: MapTileCache.tileProvider,
      ),
    );

    final tileCount = await const FMTCStore(MapTileCache.storeName).download.countTiles(region);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => OfflineDownloadSheet(region: region, estimatedTileCount: tileCount),
    );
  }

  // ── TRACE À MAIN LEVÉE ────────────────────────────────────

  void _startDrawingTrace() {
    setState(() {
      _isEditingTrace = false;
      _isDrawingTrace = true;
      _drawPoints.clear();
    });
  }

  void _addDrawPoint(LatLng point) {
    if (_drawPoints.length >= _maxDrawPoints) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum $_maxDrawPoints points atteint')));
      return;
    }
    setState(() => _drawPoints.add(point));
  }

  void _undoLastDrawPoint() {
    if (_drawPoints.isEmpty) return;
    setState(() => _drawPoints.removeLast());
  }

  void _cancelDrawingTrace() {
    setState(() {
      _isDrawingTrace = false;
      _drawPoints.clear();
    });
  }

  Future<void> _finishDrawingTrace() async {
    if (_drawPoints.length < 2) return;
    final mapProv = context.read<MapProvider>();
    final routing = RoutingService();
    final profile = mapProv.navMode == NavMode.offroad
        ? RoutingProfile.cyclingMountain
        : RoutingProfile.drivingCar;

    setState(() => _isComputingDrawnRoute = true);
    RouteResult route;
    try {
      route = await routing.fetchMultiPointRoute(
        waypoints: List.of(_drawPoints), profile: profile,
      );
    } on RoutingException catch (e) {
      if (mounted) {
        setState(() => _isComputingDrawnRoute = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isComputingDrawnRoute = false);

    final name = await _promptTraceName();
    if (name == null || !mounted) return;

    final trace = TraceModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      points: route.polyline.map((p) => TracePoint(position: p)).toList(),
      source: 'created',
    );

    final traceProv = context.read<TraceProvider>();
    final repo = context.read<RideRepository>();
    await traceProv.setCreatedTrace(trace, repository: repo);

    setState(() {
      _isDrawingTrace = false;
      _drawPoints.clear();
    });
    if (mounted) _showGpxGuidanceChooser(trace);
  }

  Future<String?> _promptTraceName() async {
    final ctrl = TextEditingController(
      text: 'Trace du ${DateTime.now().day}/${DateTime.now().month}',
    );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        title: const Text('Nommer la trace', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  // Barre flottante affichée pendant le dessin — compteur de points et
  // actions (annuler le dernier, effacer, terminer).
  Widget _buildDrawTraceBar() {
    if (!_isDrawingTrace) return const SizedBox.shrink();
    return Positioned(
      left: 12, right: 12,
      bottom: AppSizes.statsBarHeight + 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgPanel.withValues(alpha: .95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A3E)),
        ),
        child: Row(
          children: [
            Text('${_drawPoints.length}/$_maxDrawPoints points', style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.undo, color: Colors.white70, size: 20),
              onPressed: _drawPoints.isEmpty ? null : _undoLastDrawPoint,
              tooltip: 'Annuler le dernier point',
            ),
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.statusRed, size: 20),
              onPressed: _cancelDrawingTrace,
              tooltip: 'Annuler',
            ),
            FilledButton.icon(
              onPressed: (_drawPoints.length < 2 || _isComputingDrawnRoute) ? null : _finishDrawingTrace,
              icon: _isComputingDrawnRoute
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18),
              label: const Text('Terminer'),
            ),
          ],
        ),
      ),
    );
  }

  // ── ÉDITION DE TRACE ──────────────────────────────────────
  // Points-clés initiaux = ceux déjà repérés par le guidage virage par
  // virage (départ, chaque manœuvre, arrivée) : une simplification pratique
  // de la trace brute, réutilisée telle quelle plutôt que de ré-implémenter
  // un algorithme de simplification de ligne.
  void _startEditingTrace(TraceModel trace) {
    final derived = GpxRouteDeriver.deriveTurnByTurn(trace);
    final waypoints = <LatLng>[
      trace.points.first.position,
      ...derived.steps
          .where((s) => s.maneuver != ManeuverType.arrive)
          .map((s) => s.location),
      trace.points.last.position,
    ];
    setState(() {
      _isDrawingTrace = false;
      _isEditingTrace = true;
      _editingSourceTrace = trace;
      _editWaypoints
        ..clear()
        ..addAll(waypoints);
      _editedPolyline = null;
    });
  }

  // Un tap hors marqueur insère un point à l'endroit du tracé édité le
  // plus proche — pas forcément pile sur la ligne, ce qui permet justement
  // de forcer un détour pour contourner un passage interdit.
  void _insertEditPoint(LatLng point) {
    if (_editWaypoints.length < 2) return;
    final nearest = nearestPointOnPolyline(point, _editWaypoints);
    setState(() => _editWaypoints.insert(nearest.segmentIndex + 1, point));
    _recomputeEditedRoute();
  }

  void _showEditPointMenu(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.statusRed),
              title: const Text('Supprimer ce point', style: TextStyle(color: Colors.white)),
              enabled: _editWaypoints.length > 2,
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _editWaypoints.removeAt(index));
                _recomputeEditedRoute();
              },
            ),
            ListTile(
              leading: const Icon(Icons.first_page, color: AppColors.orange),
              title: const Text('Couper avant ce point', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Supprime tout ce qui précède', style: TextStyle(color: Colors.white54, fontSize: 12)),
              enabled: index > 0,
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _editWaypoints.removeRange(0, index));
                _recomputeEditedRoute();
              },
            ),
            ListTile(
              leading: const Icon(Icons.last_page, color: AppColors.orange),
              title: const Text('Couper après ce point', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Supprime tout ce qui suit', style: TextStyle(color: Colors.white54, fontSize: 12)),
              enabled: index < _editWaypoints.length - 1,
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _editWaypoints.removeRange(index + 1, _editWaypoints.length));
                _recomputeEditedRoute();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recomputeEditedRoute() async {
    if (_editWaypoints.length < 2) {
      setState(() => _editedPolyline = null);
      return;
    }
    setState(() => _isRecomputingEdit = true);
    final mapProv = context.read<MapProvider>();
    final profile = mapProv.navMode == NavMode.offroad
        ? RoutingProfile.cyclingMountain
        : RoutingProfile.drivingCar;
    try {
      final route = await RoutingService().fetchMultiPointRoute(
        waypoints: List.of(_editWaypoints), profile: profile,
      );
      if (!mounted) return;
      setState(() {
        _editedPolyline = route.polyline;
        _isRecomputingEdit = false;
      });
    } on RoutingException catch (e) {
      if (!mounted) return;
      setState(() => _isRecomputingEdit = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _cancelEditingTrace() {
    setState(() {
      _isEditingTrace = false;
      _editingSourceTrace = null;
      _editWaypoints.clear();
      _editedPolyline = null;
    });
  }

  Future<void> _saveEditedTrace() async {
    final polyline = _editedPolyline;
    if (polyline == null) return;

    final source = _editingSourceTrace;
    final trace = TraceModel(
      id: source?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: source?.name ?? 'Trace éditée',
      points: polyline.map((p) => TracePoint(position: p)).toList(),
      source: 'created',
    );

    final traceProv = context.read<TraceProvider>();
    final repo = context.read<RideRepository>();
    await traceProv.setCreatedTrace(trace, repository: repo);

    if (!mounted) return;
    setState(() {
      _isEditingTrace = false;
      _editingSourceTrace = null;
      _editWaypoints.clear();
      _editedPolyline = null;
    });
  }

  // Barre flottante affichée pendant l'édition — nombre de points et
  // actions (annuler, enregistrer).
  Widget _buildEditTraceBar() {
    if (!_isEditingTrace) return const SizedBox.shrink();
    return Positioned(
      left: 12, right: 12,
      bottom: AppSizes.statsBarHeight + 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgPanel.withValues(alpha: .95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A3E)),
        ),
        child: Row(
          children: [
            Flexible(
              child: Text(
                '${_editWaypoints.length} points — tape un point pour le modifier, ailleurs pour en ajouter un',
                style: const TextStyle(color: Colors.white, fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.statusRed, size: 20),
              onPressed: _cancelEditingTrace,
              tooltip: 'Annuler',
            ),
            FilledButton.icon(
              onPressed: (_editedPolyline == null || _isRecomputingEdit) ? null : _saveEditedTrace,
              icon: _isRecomputingEdit
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _openPoiSearchSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PoiSearchSheet(locationService: _locationService),
    );
  }

  void _showPoiDetails(PoiModel poi) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${poi.category.emoji} ${poi.name}', style: const TextStyle(
                fontFamily: 'Rajdhani', fontSize: 18, fontWeight: FontWeight.w700,
                color: Colors.white,
              )),
              const SizedBox(height: 4),
              Text(poi.category.label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              if (poi.address != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.place_outlined, color: AppColors.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(poi.address!, style: const TextStyle(color: Colors.white70, fontSize: 13))),
                ]),
              ],
              if (poi.phone != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.phone_outlined, color: AppColors.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Text(poi.phone!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ]),
              ],
              if (poi.website != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.language, color: AppColors.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(poi.website!, style: const TextStyle(color: AppColors.blue, fontSize: 13),
                    overflow: TextOverflow.ellipsis)),
                ]),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _startGuidanceTo(poi.position);
                  },
                  icon: const Icon(Icons.directions),
                  label: const Text('Guider ici'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF2A2A3E)),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── HUD PLEIN ÉCRAN ───────────────────────────────────────
  Widget _buildFullscreenHud() {
    final snap = _locationService.lastSnapshot;
    final guidance = context.watch<GuidanceProvider>();
    final speedLimit = guidance.isActive ? guidance.speedLimitKmh : null;
    return Positioned(
      bottom: 16,
      left: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vitesse (+ limite en guidage, si connue)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.65),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '${snap?.speedKmh.toStringAsFixed(0) ?? '--'}',
                      style: const TextStyle(
                        fontSize: 36, fontWeight: FontWeight.w700,
                        color: Colors.white, fontFamily: 'Rajdhani',
                      ),
                    ),
                    const Text('km/h', style: TextStyle(fontSize: 11, color: Colors.white54)),
                  ],
                ),
              ),
              if (speedLimit != null) ...[
                const SizedBox(width: 8),
                SpeedLimitBadge(limitKmh: speedLimit),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Cap
          if (snap != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.65),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _headingLabel(snap.headingDeg),
                style: const TextStyle(fontSize: 16, color: Colors.white, fontFamily: 'Rajdhani'),
              ),
            ),
        ],
      ),
    );
  }

  // ── BOUTON PLEIN ÉCRAN — SORTIE ───────────────────────────
  Widget _buildFullscreenExitBtn() {
    return Positioned(
      bottom: 16, right: 16,
      child: GestureDetector(
        onTap: context.read<MapProvider>().exitFullscreen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.65),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fullscreen_exit, color: Colors.white, size: 18),
              SizedBox(width: 4),
              Text('Quitter', style: TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // ── PANNEAU PAYSAGE ───────────────────────────────────────
  Widget _buildLandscapePanel() {
    final snap      = _locationService.lastSnapshot;
    final traceProv = context.watch<TraceProvider>();
    final fuelProv  = context.watch<FuelProvider>();
    final groupProv = context.watch<GroupProvider>();

    return Container(
      color: AppColors.bgPanel,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rappel « Toujours en balade ? » — les commandes elles-mêmes
          // sont sur la carte, dans la colonne du SOS.
          const RecordingReminder(),
          // Titre
          const Text('NAVIGATION', style: TextStyle(
            fontFamily: 'Rajdhani', fontSize: 13,
            color: AppColors.textMuted, letterSpacing: 1,
          )),
          const SizedBox(height: 10),
          // Stats en grille
          _landscapeSpeedStat(snap),
          _landscapeStat('ALTITUDE', '${snap?.altitudeMeters.toStringAsFixed(0) ?? '--'} m', Colors.white),
          if (traceProv.hasTrace && snap != null)
            _landscapeStat('RESTE',
              '${traceProv.remainingKm(snap.position.latitude, snap.position.longitude).toStringAsFixed(1)} km',
              AppColors.statusGreen,
            ),
          _landscapeStat('CARBU.', '${fuelProv.rangeKm.toStringAsFixed(0)} km', fuelProv.isLow ? AppColors.statusRed : AppColors.statusGreen),
          const Divider(height: 20),
          // Membres du groupe
          if (groupProv.groupActive) ...[
            const Text('GROUPE', style: TextStyle(
              fontFamily: 'Rajdhani', fontSize: 12,
              color: AppColors.textMuted, letterSpacing: 1,
            )),
            const SizedBox(height: 6),
            ...groupProv.members.take(5).map((m) => _groupMemberRow(m)),
            const Divider(height: 20),
          ],
          const Spacer(),
          // ── Contrôles cartographiques ─────────────────────
          const Divider(height: 16),
          Row(
            children: [
              // Mode de navigation — offroad / route / 4x4
              Expanded(child: _landscapeCtrlBtn(
                switch (context.watch<MapProvider>().navMode) {
                  NavMode.offroad => Icons.terrain,
                  NavMode.route => Icons.route,
                  NavMode.fourByFour => Icons.directions_car,
                },
                context.watch<MapProvider>().navMode.label,
                true,
                () => context.read<MapProvider>().toggleNavMode(),
              )),
              const SizedBox(width: 6),
              // Sélecteur de couche
              Expanded(child: _landscapeCtrlBtn(
                Icons.layers_outlined,
                'Couche',
                false,
                () => _showLayerSelector(),
              )),
              const SizedBox(width: 6),
              // Import GPX
              Expanded(child: _landscapeCtrlBtn(
                Icons.upload_file,
                'GPX',
                context.watch<TraceProvider>().hasTrace,
                () => _showImportSheet(),
              )),
            ],
          ),
          const SizedBox(height: 8),
          // SOS compact
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push(AppRoutes.sos),
              icon: const Icon(Icons.emergency, size: 18),
              label: const Text('SOS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _landscapeSpeedStat(GpsSnapshot? snap) {
    final guidance = context.watch<GuidanceProvider>();
    final speedLimit = guidance.isActive ? guidance.speedLimitKmh : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('VITESSE', style: TextStyle(fontSize: 11, color: AppColors.textMuted, letterSpacing: .5)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${snap?.speedKmh.toStringAsFixed(0) ?? '--'} km/h', style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.orange, fontFamily: 'Rajdhani')),
              if (speedLimit != null) ...[
                const SizedBox(width: 6),
                SpeedLimitBadge(limitKmh: speedLimit, size: 26),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _landscapeStat(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, letterSpacing: .5)),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color, fontFamily: 'Rajdhani')),
        ],
      ),
    );
  }

  Widget _groupMemberRow(GroupMember m) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          CircleAvatar(radius: 10, backgroundColor: const Color(0xFF1565C0),
            child: Text(m.name.isNotEmpty ? m.name[0] : '?', style: const TextStyle(fontSize: 9, color: Colors.white))),
          const SizedBox(width: 6),
          Text(m.name, style: const TextStyle(fontSize: 11, color: Colors.white)),
          const Spacer(),
          Text(
            m.isSharing ? '${m.speedKmh?.toStringAsFixed(0) ?? '-'} km/h' : 'masqué',
            style: TextStyle(fontSize: 10, color: m.isSharing ? AppColors.statusGreen : AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  // ── COMMANDES LATERALES : SOS puis enregistrement ─────────
  //
  // Empilées sur le bord gauche. L'ancien bandeau d'enregistrement prenait
  // toute la largeur en bas de l'écran et recouvrait les onglets ; en colonne
  // il ne masque plus rien, en portrait comme en paysage.
  Widget _buildSideControls() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SosButton(key: _tutoSosKey, onPressed: () => context.push(AppRoutes.sos)),
          const SizedBox(height: 8),
          KeyedSubtree(key: _tutoRecordingKey, child: const RecordingPanel()),
        ],
      ),
    );
  }

  // ── BANDEAU DE GUIDAGE (paysage et plein écran) ───────────
  //
  // En portrait fenêtré le bandeau se pose en bas (voir
  // _buildGuidanceBannerBottom) ; partout ailleurs il se pose en haut de la
  // carte, à droite de la colonne SOS/enregistrement qui occupe le même bord.
  Widget _buildGuidanceBanner() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: _guidanceBannerLeft,
      right: 8,
      child: const GuidanceBanner(),
    );
  }

  // ── BANDEAU DE GUIDAGE (portrait fenêtré) ─────────────────
  // En bas, au-dessus de la barre de stats. La colonne de contrôles carte
  // occupe le même coin bas-droit : on lui laisse sa largeur pour ne pas
  // recouvrir le bouton plein écran.
  Widget _buildGuidanceBannerBottom() {
    return const Positioned(
      left: 8,
      right: 12 + AppSizes.iconButtonSize + 8,
      bottom: AppSizes.statsBarHeight + 16,
      child: GuidanceBanner(showManeuverTile: false),
    );
  }

  // ── CARRÉ (ROND) FLÈCHE DE MANŒUVRE — portrait normal ────
  // Positionné sous la rangée d'icônes de l'en-tête (dont Réglages, à
  // droite) : top = marge de sécurité + hauteur de l'en-tête (icônes 52 +
  // paddings 4/8) + un petit espace.
  Widget _buildManeuverTileTop() {
    final guidance = context.watch<GuidanceProvider>();
    if (!guidance.isActive) return const SizedBox.shrink();
    final step = guidance.mode == GuidanceMode.gpxAlert ? null : guidance.currentStep;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 4 + AppSizes.iconButtonSize + 8 + 8,
      right: 12,
      child: ManeuverTile(step: step, distanceToNextStepMeters: guidance.distanceToNextStepMeters),
    );
  }

  // ── BADGE SOLO ────────────────────────────────────────────
  Widget _buildSoloBadge() {
    final soloActive = context.watch<SoloProvider>().soloActive;
    if (!soloActive) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 12,
      child: GestureDetector(
        onTap: () => context.push(AppRoutes.solo),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.green.withOpacity(.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.statusGreen),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield, color: Colors.white, size: 14),
              SizedBox(width: 4),
              Text('Solo ON', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ── MARQUEURS ────────────────────────────────────────────
  Widget _traceEndpoint(Color color) => Container(
    decoration: BoxDecoration(shape: BoxShape.circle, color: color,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: [BoxShadow(color: color.withOpacity(.4), blurRadius: 6)],
    ),
  );

  Widget _poiMarker(PoiModel poi) => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Color(poi.category.colorValue),
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3), blurRadius: 4)],
    ),
    alignment: Alignment.center,
    child: Text(poi.category.emoji, style: const TextStyle(fontSize: 16)),
  );

  Widget _editPointMarker(int number) => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.blue,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3), blurRadius: 4)],
    ),
    alignment: Alignment.center,
    child: Text('$number', style: const TextStyle(
      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
  );

  Widget _drawPointMarker(int number) => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.orange,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3), blurRadius: 4)],
    ),
    alignment: Alignment.center,
    child: Text('$number', style: const TextStyle(
      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
  );

  Widget _riderMarker(double heading) => Transform.rotate(
    angle: heading * (3.14159 / 180),
    child: Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.blue,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [BoxShadow(color: AppColors.blue.withOpacity(.5), blurRadius: 8)],
      ),
      child: const Icon(Icons.navigation, color: Colors.white, size: 16),
    ),
  );

  double _peerOpacity(DateTime? lastUpdate) {
    if (lastUpdate == null) return 1.0;
    final age = DateTime.now().difference(lastUpdate);
    if (age < const Duration(seconds: 30)) return 1.0;
    return 0.4; // au-delà de 30s et jusqu'à 2min (filtré plus haut) : estompé
  }

  Widget _memberMarker(String name, String colorHex, [double opacity = 1.0]) {
    final color = Color(int.parse('0xFF${colorHex.replaceFirst('#', '')}'));
    // Le remplissage porte tout l'estompage (position pair vieillissante) ;
    // le contour et la lettre restent proches de l'opacité pleine (plancher
    // 0.55) pour que le marqueur garde un contour net sur fond de carte
    // clair (satellite, IGN) même une fois estompé — sinon il se fond dans
    // le fond de carte au lieu de lire comme "position pas à jour".
    final crispness = 0.55 + 0.45 * opacity;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
        border: Border.all(color: Colors.white.withValues(alpha: crispness), width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .25 * crispness), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: Center(child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: crispness)),
      )),
    );
  }

  Widget _rallyMarker() => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle, color: AppColors.red,
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: const Center(child: Text('R',
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))),
  );

  // ── UTILITAIRES ──────────────────────────────────────────
  Widget _landscapeCtrlBtn(IconData icon, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color:        active ? AppColors.orange.withValues(alpha: .15) : AppColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: active ? AppColors.orange : const Color(0xFF2A2A3E)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? AppColors.orange : AppColors.textSecondary),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(
              fontSize: 10, fontFamily: 'Rajdhani',
              color: active ? AppColors.orange : AppColors.textSecondary,
            )),
          ],
        ),
      ),
    );
  }

  // 44pt : seuil minimal Apple pour une cible tactile, en dessous duquel
  // ces boutons d'en-tête étaient trop petits pour être fiables en conduite.
  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: GlassPuck(icon: icon, color: AppColors.orange, size: 44, iconSize: 22),
  );

  Widget _mapCtrlBtn(IconData icon, VoidCallback onTap,
      {bool active = false, Color activeColor = AppColors.orange}) {
    return GestureDetector(
      onTap: onTap,
      child: GlassPuck(icon: icon, color: activeColor, active: active),
    );
  }

  String _headingLabel(double deg) {
    if (deg < 22.5 || deg >= 337.5) return '↑ N';
    if (deg < 67.5)  return '↗ NE';
    if (deg < 112.5) return '→ E';
    if (deg < 157.5) return '↘ SE';
    if (deg < 202.5) return '↓ S';
    if (deg < 247.5) return '↙ SO';
    if (deg < 292.5) return '← O';
    return '↖ NO';
  }

  void _showImportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const GpxImportSheet(),
    );
  }

  void _showGpxGuidanceChooser(TraceModel trace) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Guidage sur la trace', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_active, color: AppColors.orange),
              title: const Text('Alerte de déviation', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Suis la trace, prévient si tu t\'en éloignes.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _startGuidanceOnTrace(trace, GuidanceMode.gpxAlert);
              },
            ),
            ListTile(
              leading: const Icon(Icons.turn_right, color: AppColors.orange),
              title: const Text('Guidage virage par virage', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Instructions dérivées de la trace.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _startGuidanceOnTrace(trace, GuidanceMode.gpxTurnByTurn);
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined, color: AppColors.orange),
              title: const Text('Roadbook', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Cap, distances et pictogrammes façon carnet de rallye.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push(AppRoutes.roadbook);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_road, color: AppColors.orange),
              title: const Text('Éditer la trace', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Couper, ajouter ou supprimer des points, contourner un passage.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _startEditingTrace(trace);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _startGuidanceOnTrace(TraceModel trace, GuidanceMode mode) {
    final guidance = context.read<GuidanceProvider>();
    guidance.startOnTrace(trace, mode);
    _applyVoiceMutePreference(guidance, context.read<SettingsProvider>());
  }

  // Ouvre directement le champ de saisie, sans passer par l'icône repliée :
  // choisir ce segment du menu radial est déjà le geste d'ouverture.
  void _openSearchSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: MapSearchBar(
          mapController: _mapController,
          startVisible: true,
          onResultSelected: () => Navigator.of(context).pop(),
          onGuide: _startGuidanceTo,
        ),
      ),
    );
  }

  void _showLongPressSheet(LatLng point) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.directions, color: AppColors.orange),
              title: const Text('Guider ici', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _startGuidanceTo(point);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_border, color: AppColors.orange),
              title: const Text('Ajouter aux favoris', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _promptAddFavorite(point);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startGuidanceTo(LatLng destination) async {
    final origin = _locationService.lastSnapshot?.position;
    if (origin == null) return;

    final mapProv = context.read<MapProvider>();
    final settings = context.read<SettingsProvider>();
    // ORS n'a pas de profil "4x4" dédié : le mode réutilise le profil route,
    // seul à couvrir des pistes carrossables par un véhicule à quatre roues.
    final profile = mapProv.navMode == NavMode.offroad
        ? RoutingProfile.cyclingMountain
        : RoutingProfile.drivingCar;
    final avoid = <AvoidFeature>{
      if (settings.guidanceAvoidHighways) AvoidFeature.highways,
      if (settings.guidanceAvoidTolls) AvoidFeature.tollways,
      if (settings.guidanceAvoidFerries) AvoidFeature.ferries,
    };

    final guidance = context.read<GuidanceProvider>();
    final ok = await guidance.startToDestination(
      origin: origin, destination: destination, profile: profile, avoid: avoid,
      preferCurvyRoutes: settings.guidancePreferCurvy,
    );

    if (ok) {
      _applyVoiceMutePreference(guidance, settings);
    } else if (mounted) {
      final error = guidance.error ?? "Impossible de calculer l'itinéraire";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  // Le guidage ne connaît pas les Réglages (frontière assumée) : c'est au
  // démarrage, ici, qu'on lui transmet le choix persisté de couper la voix.
  // Sans cela l'interrupteur des Réglages n'aurait aucun effet et un mute
  // décidé en cours de route ne survivrait pas au redémarrage.
  void _applyVoiceMutePreference(GuidanceProvider guidance, SettingsProvider settings) {
    if (settings.guidanceVoiceMuted != guidance.isMuted) guidance.toggleMute();
  }

  Future<void> _openFavorites() async {
    final place = await context.push<FavoritePlace>(AppRoutes.favorites);
    if (place == null) return;
    await _startGuidanceTo(place.position);
  }

  Future<void> _promptAddFavorite(LatLng point) async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        title: const Text('Nom du favori', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Ex: Garage'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(nameCtrl.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    await context.read<FavoritesProvider>().add(name, point);
  }

  void _showLayerSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const LayerSelectorSheet(),
    );
  }
}
