import '../models/models.dart';

/// Source of truth for the house. Implementations: demo data, Tuya Cloud,
/// and the hybrid local-first repository.
abstract interface class HomeRepository {
  Future<HomeSnapshot> load();

  /// Turns one output on or off. Throws on failure so the UI can roll back
  /// its optimistic update.
  Future<void> setChannel(Channel channel, bool on);

  /// Latest state of every channel, used for periodic refresh.
  Future<List<Channel>> refresh(List<Channel> current);

  /// Channels whose state a device reported on its own (local push). Only
  /// the changed channels are emitted.
  Stream<List<Channel>> get pushes;

  /// A newer full snapshot, e.g. the cloud answering after the panel
  /// started from its cache.
  Stream<HomeSnapshot> get snapshots;
}
