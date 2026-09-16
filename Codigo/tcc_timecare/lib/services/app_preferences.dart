import 'package:flutter/material.dart';

class AppPreferences extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  double _textScale = 1;
  bool _highContrast = false;

  ThemeMode get themeMode => _themeMode;
  double get textScale => _textScale;
  bool get highContrast => _highContrast;

  void update({ThemeMode? themeMode, double? textScale, bool? highContrast}) {
    if (textScale != null) {
      textScale = textScale.isFinite ? textScale.clamp(.9, 1.4) : 1;
    }
    final changed =
        (themeMode != null && themeMode != _themeMode) ||
        (textScale != null && textScale != _textScale) ||
        (highContrast != null && highContrast != _highContrast);
    if (!changed) return;
    _themeMode = themeMode ?? _themeMode;
    _textScale = textScale ?? _textScale;
    _highContrast = highContrast ?? _highContrast;
    notifyListeners();
  }
}

final appPreferences = AppPreferences();
