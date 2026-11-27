import 'package:shared_preferences/shared_preferences.dart';

import '../models/panel_layout.dart';

/// [LayoutStore] in Android SharedPreferences.
///
/// App data survives updates (`adb install -r`, a new APK over the old one);
/// it is only lost if the app is uninstalled or its data is cleared.
class PrefsLayoutStore implements LayoutStore {
  static const _key = 'panel_layout_v1';

  @override
  Future<PanelLayout?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      return raw == null ? null : PanelLayout.decode(raw);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(PanelLayout? layout) async {
    final prefs = await SharedPreferences.getInstance();
    if (layout == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, layout.encode());
    }
  }
}
