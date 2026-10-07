import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final box = Hive.box('app_settings');
      final value = box.get('theme_mode', defaultValue: 'light')?.toString();
      _mode = value == 'dark' ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      _mode = ThemeMode.light;
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    try {
      await Hive.box('app_settings').put(
        'theme_mode',
        _mode == ThemeMode.dark ? 'dark' : 'light',
      );
    } catch (_) {}
  }
}

final appThemeController = ThemeController();
