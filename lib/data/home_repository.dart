import '../models/models.dart';

/// Source of truth for the house. Implementations: demo data, Tuya Cloud,
/// and (next) Tuya local LAN control.
abstract interface class HomeRepository {
  Future<HomeSnapshot> load();

  /// Turns one output on or off. Throws on failure so the UI can roll back
  /// its optimistic update.
  Future<void> setChannel(Channel channel, bool on);

  /// Latest state of every channel, used for periodic refresh.
  Future<List<Channel>> refresh(List<Channel> current);
}
