import 'package:flutter/foundation.dart';

class FuelProvider extends ChangeNotifier {
  double _tankLiters     = 20.0;
  double _consumptionL100 = 5.0;
  double _currentFuelL   = 20.0;  // niveau actuel
  int    _searchRadiusKm = 20;

  double get tankLiters      => _tankLiters;
  double get consumptionL100 => _consumptionL100;
  double get currentFuelL    => _currentFuelL;
  int    get searchRadiusKm  => _searchRadiusKm;

  double get rangeKm => (_currentFuelL / _consumptionL100) * 100;
  double get fillPercent => (_currentFuelL / _tankLiters).clamp(0.0, 1.0);

  bool get isLow      => fillPercent < 0.25;
  bool get isCritical => fillPercent < 0.10;

  void setTank(double liters) {
    _tankLiters = liters;
    if (_currentFuelL > liters) _currentFuelL = liters;
    notifyListeners();
  }

  void setConsumption(double l100) {
    _consumptionL100 = l100;
    notifyListeners();
  }

  void setCurrentFuel(double liters) {
    _currentFuelL = liters.clamp(0, _tankLiters);
    notifyListeners();
  }

  void setSearchRadius(int km) {
    _searchRadiusKm = km;
    notifyListeners();
  }

  void refuel() {
    _currentFuelL = _tankLiters;
    notifyListeners();
  }
}
