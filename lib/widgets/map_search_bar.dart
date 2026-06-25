import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../app/theme.dart';

class MapSearchBar extends StatefulWidget {
  final MapController mapController;

  const MapSearchBar({super.key, required this.mapController});

  @override
  State<MapSearchBar> createState() => _MapSearchBarState();
}

class _MapSearchBarState extends State<MapSearchBar> {
  final _ctrl   = TextEditingController();
  final _focus  = FocusNode();
  bool _visible = false;
  bool _loading = false;
  List<_GeoResult> _results = [];

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _visible = !_visible;
      if (_visible) _focus.requestFocus();
      else { _ctrl.clear(); _results = []; }
    });
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) { setState(() => _results = []); return; }

    // Coordonnées GPS directes : "48.8566, 2.3522"
    final coords = _parseCoords(q);
    if (coords != null) {
      setState(() => _results = [_GeoResult('📍 Coordonnées : $q', coords)]);
      return;
    }

    setState(() { _loading = true; _results = []; });
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(q)}&format=json&limit=5&accept-language=fr',
      );
      final resp = await http.get(uri, headers: {
        'User-Agent': 'MotoOffroad4x4/1.0 (contact@motooffroad.app)',
      });
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        setState(() => _results = data.map((e) => _GeoResult(
          e['display_name'] as String,
          LatLng(double.parse(e['lat'] as String), double.parse(e['lon'] as String)),
        )).toList());
      }
    } catch (_) {
      // silently fail — no network
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goTo(_GeoResult result) {
    widget.mapController.move(result.position, 14);
    _toggle();
  }

  LatLng? _parseCoords(String text) {
    // Formats : "48.8566, 2.3522" ou "48.8566 2.3522"
    final re = RegExp(r'^(-?\d+\.?\d*)[,\s]+(-?\d+\.?\d*)$');
    final m  = re.firstMatch(text.trim());
    if (m == null) return null;
    final lat = double.tryParse(m.group(1)!);
    final lon = double.tryParse(m.group(2)!);
    if (lat == null || lon == null) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return LatLng(lat, lon);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Bouton loupe
        _searchToggleButton(),

        // Champ de recherche + résultats
        if (_visible) ...[
          const SizedBox(height: 6),
          _searchField(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: SizedBox(height: 20, width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange)),
            ),
          if (_results.isNotEmpty) _resultsList(),
        ],
      ],
    );
  }

  Widget _searchToggleButton() {
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: _visible
              ? AppColors.orange.withValues(alpha: .2)
              : AppColors.bgPanel.withValues(alpha: .95),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _visible ? AppColors.orange : const Color(0xFF2A2A3E)),
        ),
        child: Icon(
          _visible ? Icons.close : Icons.search,
          color: _visible ? AppColors.orange : Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _searchField() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: AppColors.bgPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.orange.withValues(alpha: .5)),
      ),
      child: TextField(
        controller:  _ctrl,
        focusNode:   _focus,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: const InputDecoration(
          hintText:        'Adresse ou lat, lon ...',
          hintStyle:       TextStyle(fontSize: 12),
          prefixIcon:      Icon(Icons.search, size: 18),
          isDense:         true,
          border:          InputBorder.none,
          contentPadding:  EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged:   _search,
        onSubmitted: _search,
      ),
    );
  }

  Widget _resultsList() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 220),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color:        AppColors.bgPanel,
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: ListView.separated(
        padding:       EdgeInsets.zero,
        shrinkWrap:    true,
        itemCount:     _results.length,
        separatorBuilder: (_, __) => const Divider(color: Color(0xFF2A2A3E), height: 1),
        itemBuilder: (_, i) {
          final r = _results[i];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.place, color: AppColors.orange, size: 16),
            title: Text(
              r.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            onTap: () => _goTo(r),
          );
        },
      ),
    );
  }
}

class _GeoResult {
  final String displayName;
  final LatLng position;

  const _GeoResult(this.displayName, this.position);
}
