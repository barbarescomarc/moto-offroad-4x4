import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/favorite_place.dart';

class FavoritesProvider extends ChangeNotifier {
  static const _kFavorites = 'favorite_places';
  final _uuid = const Uuid();

  List<FavoritePlace> _places = [];
  List<FavoritePlace> get places => List.unmodifiable(_places);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _places = _decode(prefs.getString(_kFavorites));
    notifyListeners();
  }

  List<FavoritePlace> _decode(String? raw) {
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => FavoritePlace.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFavorites, jsonEncode(_places.map((p) => p.toJson()).toList()));
  }

  Future<void> add(String name, LatLng position) async {
    _places.add(FavoritePlace(id: _uuid.v4(), name: name, position: position));
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _places.removeWhere((p) => p.id == id);
    await _save();
    notifyListeners();
  }
}
