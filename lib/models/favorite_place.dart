import 'package:latlong2/latlong.dart';

class FavoritePlace {
  final String id;
  final String name;
  final LatLng position;

  const FavoritePlace({
    required this.id,
    required this.name,
    required this.position,
  });

  Map<String, dynamic> toJson() => {
    'id':   id,
    'name': name,
    'lat':  position.latitude,
    'lon':  position.longitude,
  };

  factory FavoritePlace.fromJson(Map<String, dynamic> j) => FavoritePlace(
    id:   j['id'] as String,
    name: j['name'] as String,
    position: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
  );
}
