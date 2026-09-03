import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
import '../../services/location_service.dart';
import '../../services/routing_service.dart';
import '../../widgets/sos_button.dart';
import '../../widgets/mode_switch.dart';
import '../../widgets/stats_bar.dart';
import '../../widgets/layer_selector.dart';
import '../../widgets/gpx_import_sheet.dart';
import '../../widgets/glass_control.dart';
import '../../widgets/map_search_bar.dart';
import '../../widgets/radial_action_menu.dart';
import '../../widgets/recording_panel.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final _mapController = MapController();
  final _locationService = LocationService();

  bool _mapReady = false;

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
  }

  // Dernier état transmis au système, pour ne pas rappeler le canal natif
  // à chaque reconstruction.
  bool _wakelockOn = false;

  @override
  void dispose() {
    _navBarHideTimer?.cancel();
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

      // Centrer la carte sur la position si suivi actif
      if (mapProv.followPosition && _mapReady) {
        _mapController.move(snap.position, _mapController.camera.zoom);
      }

      // Mise à jour position sur la trace
      traceProv.updatePosition(snap.position.latitude, snap.position.longitude);
    });
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

          // ── HUD fullscreen ───────────────────────────────
          if (isFullscreen) ...[
            _buildFullscreenHud(),
            _buildSideControls(),
            _buildFullscreenExitBtn(),
          ] else ...[
            // ── Header ──────────────────────────────────────
            Positioned(top: 0, left: 0, right: 0, child: _buildHeader()),

            // ── Bouton SOS (toujours visible) ───────────────
            _buildSideControls(),

            // ── Badge Solo ──────────────────────────────────
            _buildSoloBadge(),

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
              _buildSideControls(),
              _buildSoloBadge(),
              Positioned(
                bottom: 8, right: 8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildMapControls(),
                  ],
                ),
              ),
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
    final snap      = _locationService.lastSnapshot;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: mapProv.center,
        initialZoom: mapProv.zoom,
        minZoom: 5,
        maxZoom: 18,
        onMapReady: () => setState(() => _mapReady = true),
        onTap: (_, __) {
          if (mapProv.isFullscreen) mapProv.exitFullscreen();
        },
        onLongPress: (_, point) => _showLongPressSheet(point),
        onMapEvent: (event) => _onMapEvent(event, mapProv, settings),
      ),
      children: [
        // ── Tuile de fond ──────────────────────────────────
        TileLayer(
          urlTemplate: mapProv.activeLayer.tileUrl,
          userAgentPackageName: 'app.motooffroad',
          maxZoom: 18,
        ),

        // ── Noms de rues/lieux sur fond satellite ───────────
        if (mapProv.activeLayer.labelsOverlayUrl != null)
          TileLayer(
            urlTemplate: mapProv.activeLayer.labelsOverlayUrl!,
            userAgentPackageName: 'app.motooffroad',
            maxZoom: 18,
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
          // Portion restante (orange)
          PolylineLayer(polylines: [
            Polyline(
              points: traceProv.activeTrace!.points
                  .skip(traceProv.currentIndex)
                  .map((p) => p.position)
                  .toList(),
              strokeWidth: 3.5,
              color: AppColors.traceColor,
            ),
          ]),
          // Portion parcourue (vert)
          PolylineLayer(polylines: [
            Polyline(
              points: traceProv.activeTrace!.points
                  .take(traceProv.currentIndex + 1)
                  .map((p) => p.position)
                  .toList(),
              strokeWidth: 3.5,
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
              .where((m) => m.id != 'me' && m.position != null && m.isSharing)
              .map((m) => Marker(
                    point: m.position!,
                    width: 36, height: 36,
                    child: _memberMarker(m.name, m.color),
                  ))
              .toList(),
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
  }

  // ── HEADER ────────────────────────────────────────────────
  Widget _buildHeader() {
    final traceProv = context.watch<TraceProvider>();
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
          // Nom trace
          Expanded(
            child: Text(
              traceProv.hasTrace
                  ? traceProv.activeTrace!.name
                  : 'MOTO OFFROAD 4X4',
              style: const TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: .8,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Switch offroad/route
          const ModeSwitchWidget(),
          const SizedBox(width: 4),
          // Import GPX
          _iconBtn(Icons.upload_file, () => _showImportSheet()),
          // Sélecteur de couche
          _iconBtn(Icons.layers_outlined, () => _showLayerSelector()),
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
    return Consumer3<TraceProvider, FuelProvider, MapProvider>(
      builder: (ctx, trace, fuel, map, _) {
        final snap = _locationService.lastSnapshot;
        return StatsBar(
          speedKmh:    snap?.speedKmh ?? 0,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Recentrer : appui court inchangé. Appui long puis glissement vers
        // le haut-gauche (côté opposé au bord droit de l'écran et aux
        // boutons Radar/Plein écran juste en dessous) révèle Recherche,
        // Météo et Mode Solo.
        RadialActionMenu(
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
          ],
        ),
        const SizedBox(height: 6),
        // Radar
        _mapCtrlBtn(
          Icons.radar,
          mapProv.toggleRadar,
          active: mapProv.radarEnabled,
          activeColor: AppColors.blue,
        ),
      ],
    );
  }

  // ── HUD PLEIN ÉCRAN ───────────────────────────────────────
  Widget _buildFullscreenHud() {
    final snap = _locationService.lastSnapshot;
    return Positioned(
      bottom: 16,
      left: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vitesse
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
          _landscapeStat('VITESSE', '${snap?.speedKmh.toStringAsFixed(0) ?? '--'} km/h', AppColors.orange),
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
              // Mode offroad/route
              Expanded(child: _landscapeCtrlBtn(
                Icons.terrain,
                'Offroad',
                context.watch<MapProvider>().isOffroad,
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
          SosButton(onPressed: () => context.push(AppRoutes.sos)),
          const SizedBox(height: 8),
          const RecordingPanel(),
        ],
      ),
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

  Widget _memberMarker(String name, String colorHex) {
    final color = Color(int.parse('0xFF${colorHex.replaceFirst('#', '')}'));
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle, color: color,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
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

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: GlassPuck(icon: icon, color: AppColors.orange, size: 36, iconSize: 18),
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
    final profile = mapProv.isOffroad ? RoutingProfile.cyclingMountain : RoutingProfile.drivingCar;
    final avoid = <AvoidFeature>{
      if (settings.guidanceAvoidHighways) AvoidFeature.highways,
      if (settings.guidanceAvoidTolls) AvoidFeature.tollways,
      if (settings.guidanceAvoidFerries) AvoidFeature.ferries,
    };

    final ok = await context.read<GuidanceProvider>().startToDestination(
      origin: origin, destination: destination, profile: profile, avoid: avoid,
    );

    if (!ok && mounted) {
      final error = context.read<GuidanceProvider>().error ?? "Impossible de calculer l'itinéraire";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
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
