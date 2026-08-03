import 'package:signals/signals.dart';

class ScreenStateService {
  final Signal<bool> _isNarrow = signal(false);
  
  bool get isNarrow => _isNarrow.value;
  Signal<bool> get isNarrowSignal => _isNarrow;

  static const double _narrowThreshold = 600;

  void updateScreenWidth(double width) {
    _isNarrow.value = width < _narrowThreshold;
  }

  void dispose() {
    _isNarrow.dispose();
  }
}