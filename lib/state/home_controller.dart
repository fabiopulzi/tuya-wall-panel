import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/home_repository.dart';
import '../models/models.dart';

/// Holds the house state and applies actions optimistically: the UI flips
/// immediately and rolls back if the device does not answer.
class HomeController extends ChangeNotifier {
  HomeController(this._repo, {this.refreshEvery = const Duration(seconds: 20)});

  final HomeRepository _repo;
  final Duration refreshEvery;

  String homeName = '';
  List<Room> rooms = const [];
  List<Scene> scenes = const [];
  final Map<String, Channel> _channels = {};
  final Set<String> _pending = {};

  bool loading = true;
  Object? error;

  /// Last failure message for the UI to show once.
  final ValueNotifier<String?> failures = ValueNotifier(null);

  Timer? _timer;

  Iterable<Channel> get channels => _channels.values;

  List<Channel> channelsIn(String roomId) =>
      _channels.values.where((c) => c.roomId == roomId).toList();

  bool isPending(String channelId) => _pending.contains(channelId);

  int get lightsOn => _channels.values
      .where((c) => c.kind == DeviceKind.light && c.isOn)
      .length;

  /// Running non-light loads, pumps first (they matter most at a glance).
  List<Channel> get activeLoads =>
      _channels.values
          .where((c) => c.kind != DeviceKind.light && c.isOn)
          .toList()
        ..sort(
          (a, b) => (a.kind == DeviceKind.pump ? 0 : 1).compareTo(
            b.kind == DeviceKind.pump ? 0 : 1,
          ),
        );

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final snap = await _repo.load();
      homeName = snap.homeName;
      rooms = snap.rooms;
      scenes = snap.scenes;
      _channels
        ..clear()
        ..addEntries(snap.channels.map((c) => MapEntry(c.id, c)));
      _timer?.cancel();
      _timer = Timer.periodic(refreshEvery, (_) => _refresh());
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> toggle(Channel channel) => set(channel, !channel.isOn);

  Future<void> set(Channel channel, bool on) async {
    final current = _channels[channel.id];
    if (current == null || current.isOn == on) return;

    _channels[channel.id] = current.copyWith(isOn: on);
    _pending.add(channel.id);
    notifyListeners();
    try {
      await _repo.setChannel(current, on);
    } catch (_) {
      _channels[channel.id] = current;
      failures.value = 'Não foi possível acionar "${current.name}"';
    } finally {
      _pending.remove(channel.id);
      notifyListeners();
    }
  }

  /// Turns every light of a room on/off. Plugs and pumps are left alone —
  /// nobody wants the pool filter to stop because they left the room.
  Future<void> setRoomLights(String roomId, bool on) => Future.wait([
    for (final c in channelsIn(roomId))
      if (c.kind == DeviceKind.light) set(c, on),
  ]);

  Future<void> allLightsOff() => Future.wait([
    for (final c in _channels.values)
      if (c.kind == DeviceKind.light && c.isOn) set(c, false),
  ]);

  Future<void> runScene(Scene scene) => Future.wait([
    for (final MapEntry(:key, :value) in scene.actions.entries)
      if (_channels[key] case final c?) set(c, value),
  ]);

  Future<void> _refresh() async {
    if (_pending.isNotEmpty) return;
    try {
      final fresh = await _repo.refresh(_channels.values.toList());
      if (_pending.isNotEmpty) return;
      for (final c in fresh) {
        _channels[c.id] = c;
      }
      notifyListeners();
    } catch (_) {
      // Keep the last known state; the next tick will try again.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    failures.dispose();
    super.dispose();
  }
}
