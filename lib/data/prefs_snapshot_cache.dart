import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'snapshot_cache.dart';

/// [SnapshotCache] backed by Android SharedPreferences.
class PrefsSnapshotCache implements SnapshotCache {
  static const _key = 'home_snapshot_v1';

  @override
  Future<HomeSnapshot?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      return raw == null ? null : decodeSnapshot(raw);
    } on Object {
      return null; // Corrupt or incompatible cache: start from the cloud.
    }
  }

  @override
  Future<void> write(HomeSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, encodeSnapshot(snapshot));
  }
}
