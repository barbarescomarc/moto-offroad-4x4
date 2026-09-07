// lib/widgets/poi_search_sheet.dart
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../app/theme.dart';
import '../models/poi.dart';
import '../providers/guidance_provider.dart';
import '../providers/poi_search_provider.dart';
import '../services/location_service.dart';

const _searchableCategories = [
  PoiCategory.viewpoint,
  PoiCategory.guestHouse,
  PoiCategory.naturalSite,
  PoiCategory.heritage,
];

class PoiSearchSheet extends StatefulWidget {
  final LocationService locationService;
  const PoiSearchSheet({super.key, required this.locationService});

  @override
  State<PoiSearchSheet> createState() => _PoiSearchSheetState();
}

class _PoiSearchSheetState extends State<PoiSearchSheet> {
  PoiSearchMode _mode = PoiSearchMode.aroundMe;
  final Set<PoiCategory> _selected = {PoiCategory.viewpoint};

  @override
  Widget build(BuildContext context) {
    final guidance = context.watch<GuidanceProvider>();
    final hasRoute = guidance.isActive && (guidance.route?.polyline.isNotEmpty ?? false);
    final searching = context.watch<PoiSearchProvider>().isSearching;

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A3E),
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          const SizedBox(height: 16),
          const Text('RECHERCHER DES POINTS D\'INTÉRÊT', style: TextStyle(
            fontFamily: 'Rajdhani', fontSize: 16, fontWeight: FontWeight.w700,
            color: AppColors.orange, letterSpacing: 1,
          )),
          const SizedBox(height: 4),
          const Text('Rayon de recherche : 20 km — source DATAtourisme',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 16),

          const Text('OÙ CHERCHER', style: TextStyle(
            fontFamily: 'Rajdhani', fontSize: 12, color: AppColors.textMuted, letterSpacing: 1)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _modeChip('Autour de moi', PoiSearchMode.aroundMe, enabled: true),
            _modeChip('À destination', PoiSearchMode.atDestination, enabled: hasRoute),
            _modeChip('Le long de la route', PoiSearchMode.alongRoute, enabled: hasRoute),
          ]),
          const SizedBox(height: 16),

          const Text('QUOI CHERCHER', style: TextStyle(
            fontFamily: 'Rajdhani', fontSize: 12, color: AppColors.textMuted, letterSpacing: 1)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8,
            children: _searchableCategories.map(_categoryChip).toList()),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_selected.isEmpty || searching) ? null : _search,
              icon: searching
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search),
              label: Text(searching ? 'Recherche…' : 'Rechercher'),
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeChip(String label, PoiSearchMode mode, {required bool enabled}) {
    final active = _mode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: enabled ? (_) => setState(() => _mode = mode) : null,
      labelStyle: TextStyle(
        color: !enabled ? AppColors.textMuted : (active ? Colors.white : Colors.white70),
        fontSize: 13,
      ),
      selectedColor: AppColors.orange,
      backgroundColor: AppColors.bgPanel,
      disabledColor: AppColors.bgPanel.withValues(alpha: .5),
    );
  }

  Widget _categoryChip(PoiCategory category) {
    final active = _selected.contains(category);
    return FilterChip(
      label: Text('${category.emoji} ${category.label}'),
      selected: active,
      onSelected: (selected) => setState(() {
        if (selected) {
          _selected.add(category);
        } else {
          _selected.remove(category);
        }
      }),
      labelStyle: TextStyle(color: active ? Colors.white : Colors.white70, fontSize: 13),
      selectedColor: Color(category.colorValue),
      backgroundColor: AppColors.bgPanel,
      checkmarkColor: Colors.white,
    );
  }

  Future<void> _search() async {
    final guidance = context.read<GuidanceProvider>();
    final provider = context.read<PoiSearchProvider>();
    final position = widget.locationService.lastSnapshot?.position;

    LatLng? aroundPoint;
    List<LatLng>? routePolyline;
    switch (_mode) {
      case PoiSearchMode.aroundMe:
        aroundPoint = position;
      case PoiSearchMode.atDestination:
        aroundPoint = guidance.route?.polyline.lastOrNull;
      case PoiSearchMode.alongRoute:
        routePolyline = guidance.route?.polyline;
    }

    await provider.search(
      mode: _mode,
      categories: _selected,
      aroundPoint: aroundPoint,
      routePolyline: routePolyline,
    );
    if (mounted) Navigator.pop(context);
  }
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
