import 'package:shared_preferences/shared_preferences.dart';

import '../models/panel_settings.dart';

/// [PanelSettingsStore] in SharedPreferences (survives app updates).
class PrefsPanelSettingsStore implements PanelSettingsStore {
  static const _key = 'panel_settings_v1';

  @override
  Future<PanelSettings?> read() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      return raw == null ? null : PanelSettings.decode(raw);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(PanelSettings settings) async =>
      (await SharedPreferences.getInstance()).setString(
        _key,
        settings.encode(),
      );
}
