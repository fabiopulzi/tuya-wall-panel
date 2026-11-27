import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/home_repository.dart';
import '../data/hybrid_repository.dart';
import '../models/models.dart';
import '../models/panel_layout.dart';

/// Holds the house state and applies actions optimistically: the UI flips
/// immediately and rolls back if the device does not answer.
///
/// One switch can change others: two keys wired in parallel, or Tuya
/// multi-control links. So every command is followed by quick refreshes of
/// the whole house, on top of the regular polling.
class HomeController extends ChangeNotifier {
  HomeController(
    this._repo, {
    this.refreshEvery = const Duration(seconds: 8),
    this.followUps = const [Duration(milliseconds: 1500), Duration(seconds: 4)],
    this.settleTime = const Duration(seconds: 3),
    LayoutStore? layouts,
  }) : _layouts = layouts ?? MemoryLayoutStore();

  final HomeRepository _repo;
  final LayoutStore _layouts;
  final Duration refreshEvery;

  /// Refreshes scheduled after each command, to catch linked switches.
  final List<Duration> followUps;

  /// After a command, the cloud may still report the old value for a moment;
  /// the commanded channel ignores refreshes for this long.
  final Duration settleTime;

  String homeName = '';
  List<Scene> scenes = const [];
  final Map<String, Channel> _channels = {};
  final Set<String> _pending = {};

  bool loading = true;
  Object? error;

  /// Last failure message for the UI to show once.
  final ValueNotifier<String?> failures = ValueNotifier(null);

  Timer? _timer;
  final List<Timer> _followUpTimers = [];
  final Map<String, Timer> _settling = {};
  final Map<String, int> _edits = {};
  StreamSubscription<List<Channel>>? _pushSub;
  StreamSubscription<HomeSnapshot>? _snapSub;
  bool _refreshing = false;
  bool _refreshAgain = false;

  /// Rooms and keys as the cloud describes them.
  List<Room> _baseRooms = const [];

  /// The customization made on the tablet, if any.
  PanelLayout? _layout;
  bool _layoutRead = false;

  /// [_layout] (or the cloud layout) resolved against the current keys.
  PanelLayout _view = PanelLayout(rooms: const []);

  /// Every key of the house, with its original name (hidden ones included).
  Iterable<Channel> get channels => _channels.values;

  /// Rooms shown on the panel, in order. Empty rooms are left out.
  List<Room> get rooms => [
    for (final r in _view.rooms)
      if (r.channelIds.isNotEmpty) r.toRoom(),
  ];

  /// Keys shown in a room, in order, with their panel names.
  List<Channel> channelsIn(String roomId) => [
    for (final id in _view.room(roomId)?.channelIds ?? const <String>[])
      if (_channels[id] case final c?) _display(c),
  ];

  /// Keys on the panel (not hidden), with their panel names.
  Iterable<Channel> get visibleChannels => [
    for (final r in _view.rooms) ...channelsIn(r.id),
  ];

  Channel _display(Channel c) => switch (_view.names[c.id]) {
    final name? => c.copyWith(name: name),
    null => c,
  };

  /// Name on the panel for a key.
  String nameOf(String channelId) =>
      _view.names[channelId] ?? _channels[channelId]?.name ?? channelId;

  Channel? channel(String id) => _channels[id];

  /// Smart Life room name of a key, for the settings screen.
  String? originalRoomName(String channelId) {
    final roomId = _channels[channelId]?.roomId;
    for (final r in _baseRooms) {
      if (r.id == roomId) return r.name;
    }
    return null;
  }

  bool get isCustomized => _layout != null;

  /// What the settings screen starts from: the saved layout, or the cloud
  /// layout when nothing was customized yet.
  PanelLayout get editableLayout => _view;

  /// Applies and saves a new layout (settings screen, rename on long press).
  Future<void> updateLayout(PanelLayout layout) async {
    _layout = layout;
    _rebuildView();
    notifyListeners();
    await _layouts.write(layout);
  }

  /// Back to the Smart Life rooms and names.
  Future<void> resetLayout() async {
    _layout = null;
    _rebuildView();
    notifyListeners();
    await _layouts.write(null);
  }

  Future<void> renameChannel(String channelId, String? name) =>
      updateLayout(_view.renameChannel(channelId, name));

  Future<void> hideChannel(String channelId) =>
      updateLayout(_view.moveChannel(channelId));

  void _rebuildView() {
    final channels = _channels.values.toList();
    _view = (_layout ?? PanelLayout.fromHome(_baseRooms, channels)).normalized(
      channels,
    );
  }

  bool isPending(String channelId) => _pending.contains(channelId);

  /// How many devices answer on the LAN, or null without LAN support.
  ({int local, int total})? get lanStatus => switch (_repo) {
    final HybridRepository h when h.transport != null => (
      local: h.localCount,
      total: h.localTotal,
    ),
    _ => null,
  };
  ({int local, int total})? _lastLan;

  int get lightsOn => visibleChannels
      .where((c) => c.kind == DeviceKind.light && c.isOn && c.online)
      .length;

  /// Running non-light loads, pumps first (they matter most at a glance).
  List<Channel> get activeLoads =>
      visibleChannels
          .where((c) => c.kind != DeviceKind.light && c.isOn && c.online)
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
      if (!_layoutRead) {
        _layoutRead = true;
        try {
          _layout = await _layouts.read();
        } on Object {
          _layout = null;
        }
      }
      final snap = await _repo.load();
      homeName = snap.homeName;
      _baseRooms = snap.rooms;
      scenes = snap.scenes;
      _channels
        ..clear()
        ..addEntries(snap.channels.map((c) => MapEntry(c.id, c)));
      _rebuildView();
      _pushSub ??= _repo.pushes.listen(_applyPush);
      _snapSub ??= _repo.snapshots.listen(_applySnapshot);
      _timer?.cancel();
      _timer = Timer.periodic(refreshEvery, (_) => refreshNow());
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
    _edits.update(channel.id, (n) => n + 1, ifAbsent: () => 1);
    notifyListeners();
    try {
      await _repo.setChannel(current, on);
      _settling[channel.id]?.cancel();
      _settling[channel.id] = Timer(
        settleTime,
        () => _settling.remove(channel.id),
      );
      _scheduleFollowUps();
    } catch (_) {
      _channels[channel.id] = current;
      failures.value = 'Não foi possível acionar "${nameOf(current.id)}"';
    } finally {
      _pending.remove(channel.id);
      notifyListeners();
    }
  }

  /// Turns every light of a room on/off. Plugs and pumps are left alone —
  /// nobody wants the pool filter to stop because they left the room.
  Future<void> setRoomLights(String roomId, bool on) => Future.wait([
    for (final c in channelsIn(roomId))
      if (c.kind == DeviceKind.light && c.online) set(c, on),
  ]);

  /// Hidden keys are left alone: they mirror a key that is on the panel.
  Future<void> allLightsOff() => Future.wait([
    for (final c in visibleChannels)
      if (c.kind == DeviceKind.light && c.isOn && c.online) set(c, false),
  ]);

  Future<void> runScene(Scene scene) => Future.wait([
    for (final MapEntry(:key, :value) in scene.actions.entries)
      if (_channels[key] case final c?) set(c, value),
  ]);

  /// A device reported its own state over the LAN: authoritative and
  /// instant, so it wins over everything except a command still in flight.
  void _applyPush(List<Channel> pushed) {
    var changed = false;
    for (final c in pushed) {
      final local = _channels[c.id];
      if (local == null || _pending.contains(c.id)) continue;
      if (local.isOn != c.isOn || local.online != c.online) {
        _channels[c.id] = local.copyWith(isOn: c.isOn, online: c.online);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// A newer house layout arrived (cloud sync after a cached start).
  void _applySnapshot(HomeSnapshot snap) {
    homeName = snap.homeName;
    _baseRooms = snap.rooms;
    scenes = snap.scenes;
    final previous = Map.of(_channels);
    _channels
      ..clear()
      ..addEntries(
        snap.channels.map((c) {
          final local = previous[c.id];
          final keep =
              local != null &&
              (_pending.contains(c.id) || _settling.containsKey(c.id));
          return MapEntry(c.id, keep ? c.copyWith(isOn: local.isOn) : c);
        }),
      );
    _rebuildView();
    notifyListeners();
  }

  /// Debounced: a burst of taps ("Apagar tudo") yields one set of
  /// follow-up refreshes, timed from the last command.
  void _scheduleFollowUps() {
    for (final t in _followUpTimers) {
      t.cancel();
    }
    _followUpTimers
      ..clear()
      ..addAll(followUps.map((d) => Timer(d, refreshNow)));
  }

  /// Pulls the latest state of every channel. Channels with a command in
  /// flight, still settling, or edited while the request was out keep their
  /// local state; everything else follows the cloud.
  Future<void> refreshNow() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      final editsBefore = Map.of(_edits);
      final fresh = await _repo.refresh(_channels.values.toList());
      var changed = false;
      for (final c in fresh) {
        final local = _channels[c.id];
        if (local == null ||
            _pending.contains(c.id) ||
            _settling.containsKey(c.id) ||
            _edits[c.id] != editsBefore[c.id]) {
          continue;
        }
        if (local.isOn != c.isOn || local.online != c.online) {
          _channels[c.id] = c;
          changed = true;
        }
      }
      final lan = lanStatus;
      if (lan != _lastLan) {
        _lastLan = lan;
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (_) {
      // Keep the last known state; the next tick will try again.
    } finally {
      _refreshing = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        unawaited(refreshNow());
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pushSub?.cancel();
    _snapSub?.cancel();
    for (final t in [..._followUpTimers, ..._settling.values]) {
      t.cancel();
    }
    failures.dispose();
    super.dispose();
  }
}
