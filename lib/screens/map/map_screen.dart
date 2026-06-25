import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../../app/router.dart';
import '../../providers/map_provider.dart';
import '../../providers/trace_provider.dart';
import '../../providers/group_provider.dart';
import '../../models/trace.dart' show TracePoint;
import '../../providers/fuel_provider.dart';
import '../../providers/solo_provider.dart';
import '../../services/location_service.dart';
import '../../widgets/sos_button.dart';
import '../../widgets/mode_switch.dart';
import '../../widgets/stats_bar.dart';
import '../../widgets/layer_selector.dart';
import '../../widgets/gpx_import_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final _mapController = MapController();
  final _locationService = LocationService();

  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
            _buildSosButton(),
            _buildFullscreenExitBtn(),
          ] else ...[
            // ── Header ──────────────────────────────────────
            Positioned(top: 0, left: 0, right: 0, child: _buildHeader()),

            // ── Bouton SOS (toujours visible) ───────────────
            _buildSosButton(),

            // ── Badge Solo ──────────────────────────────────
            _buildSoloBadge(),

            // ── Contrôles carte ─────────────────────────────
            Positioned(
              right: 12,
              bottom: AppSizes.statsBarHeight + 16,
              child: _buildMapControls(),
            ),

            // ── Stats bar + fullscreen btn ───────────────────
            Positioned(
              left: 0, right: 0,
              bottom: 0,
              child: Column(children: [
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
              _buildSosButton(),
              _buildSoloBadge(),
              Positioned(bottom: 8, right: 8, child: _buildMapControls()),
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
      ),
      children: [
        // ── Tuile de fond ──────────────────────────────────
        TileLayer(
          urlTemplate: mapProv.activeLayer.tileUrl,
          userAgentPackageName: 'app.motooffroad',
          maxZoom: 18,
        ),

        // ── Overlay radar pluie (RainViewer) ───────────────
        if (mapProv.radarEnabled)
          Opacity(
            opacity: 0.55,
            child: TileLayer(
              urlTemplate:
                  'https://tilecache.rainviewer.com/v2/radar/nowcast/{z}/{x}/{y}/4/1_1.png',
              userAgentPackageName: 'app.motooffroad',
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
          const SizedBox(width: 8),
          // Import GPX
          _iconBtn(Icons.upload_file, () => _showImportSheet()),
          // Sélecteur de couche
          _iconBtn(Icons.layers_outlined, () => _showLayerSelector()),
        ],
      ),
    );
  }

  // ── STATS BAR ─────────────────────────────────────────────
  Widget _buildStatsBar() {
    return Consumer3<TraceProvider, FuelProvider, MapProvider>(
      builder: (ctx, trace, fuel, map, _) {
        final snap = _locationService.lastSnapshot;
        return Column(
          children: [
            // Bouton plein écran
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: map.toggleFullscreen,
                child: Container(
                  margin: const EdgeInsets.only(right: 12, bottom: 4),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.bgPanel.withOpacity(.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2A2A3E)),
                  ),
                  child: const Icon(Icons.fullscreen, color: Colors.white, size: 18),
                ),
              ),
            ),
            StatsBar(
              speedKmh:    snap?.speedKmh ?? 0,
              remainingKm: trace.hasTrace && snap != null
                  ? trace.remainingKm(
                      snap.position.latitude, snap.position.longitude)
                  : null,
              fuelRangeKm: fuel.rangeKm,
              fuelOk:      !fuel.isLow,
              altitude:    snap?.altitudeMeters,
            ),
          ],
        );
      },
    );
  }

  // ── CONTRÔLES CARTE ──────────────────────────────────────
  Widget _buildMapControls() {
    final mapProv = context.watch<MapProvider>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Zoom +
        _mapCtrlBtn(Icons.add, () {
          _mapController.move(
            _mapController.camera.center,
            _mapController.camera.zoom + 1,
          );
        }),
        const SizedBox(height: 6),
        // Zoom -
        _mapCtrlBtn(Icons.remove, () {
          _mapController.move(
            _mapController.camera.center,
            _mapController.camera.zoom - 1,
          );
        }),
        const SizedBox(height: 6),
        // Recentrer
        _mapCtrlBtn(
          mapProv.followPosition ? Icons.my_location : Icons.location_searching,
          () {
            mapProv.toggleFollowPosition();
            final snap = _locationService.lastSnapshot;
            if (snap != null) {
              _mapController.move(snap.position, _mapController.camera.zoom);
            }
          },
          active: mapProv.followPosition,
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

  // ── BOUTON SOS ────────────────────────────────────────────
  Widget _buildSosButton() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      child: SosButton(onPressed: () => context.push(AppRoutes.sos)),
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
  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: AppColors.bgPanel.withOpacity(.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    ),
  );

  Widget _mapCtrlBtn(IconData icon, VoidCallback onTap,
      {bool active = false, Color activeColor = AppColors.orange}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(.2) : AppColors.bgPanel.withOpacity(.9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? activeColor : const Color(0xFF2A2A3E)),
        ),
        child: Icon(icon, color: active ? activeColor : Colors.white, size: 20),
      ),
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
