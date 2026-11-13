import 'package:flutter/material.dart';

/// Light / dark selection for the running app. Plain ChangeNotifier (no
/// state-management dependency); the choice is kept for the app's
/// lifetime. Persisting it across restarts would need a storage package
/// (e.g. shared_preferences) and was deliberately left out to keep the
/// dependency set minimal -- see the report.
class ThemeController extends ChangeNotifier {
  ThemeController({ThemeMode initial = ThemeMode.system}) : _mode = initial;

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  /// The effective brightness, resolving ThemeMode.system against the OS.
  Brightness effectiveBrightness(BuildContext context) => switch (_mode) {
        ThemeMode.light => Brightness.light,
        ThemeMode.dark => Brightness.dark,
        ThemeMode.system => MediaQuery.platformBrightnessOf(context),
      };

  bool isDark(BuildContext context) => effectiveBrightness(context) == Brightness.dark;

  void setMode(ThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
  }

  /// Flips between explicit light and dark (from "system", it flips the
  /// currently effective brightness).
  void toggle(BuildContext context) => setMode(isDark(context) ? ThemeMode.light : ThemeMode.dark);
}
