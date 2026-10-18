import 'package:astral_game/config/app_dimensions.dart';
import 'package:signals/signals.dart';

class ScreenStateService {
  final Signal<bool> _isNarrow = signal(false);
  
  bool get isNarrow => _isNarrow.value;
  Signal<bool> get isNarrowSignal => _isNarrow;

  void updateScreenWidth(double width) {
    _isNarrow.value = width < AppBreakpoints.narrow;
  }

  void dispose() {
    _isNarrow.dispose();
  }
}