import 'package:flutter/foundation.dart';
import '../models/ride.dart';
import '../services/ride_repository.dart';

// ── Provider — historique des sorties ────────────────────────
class RidesProvider extends ChangeNotifier {
  RidesProvider({required RideRepository repository}) : _repo = repository;

  final RideRepository _repo;
  List<Ride> _rides = [];
  bool _isLoading = false;

  List<Ride> get rides => List.unmodifiable(_rides);
  bool get isLoading => _isLoading;

  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();
    _rides = await _repo.listRides();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> rename(String id, String name) async {
    final ride = await _repo.findRide(id);
    if (ride == null) return;
    await _repo.updateRide(ride.copyWith(name: name));
    await refresh();
  }

  Future<void> setNotes(String id, String notes) async {
    final ride = await _repo.findRide(id);
    if (ride == null) return;
    await _repo.updateRide(ride.copyWith(notes: notes));
    await refresh();
  }

  Future<void> remove(String id) async {
    await _repo.deleteRide(id);
    await refresh();
  }

  Future<List<RidePoint>> pointsOf(String id) => _repo.pointsOf(id);
}
