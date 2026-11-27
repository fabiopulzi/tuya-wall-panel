import 'dart:async';

import '../models/models.dart';
import '../tuya/local/local_link.dart';
import '../tuya/local/tuya_protocol.dart';
import 'home_repository.dart';
import 'snapshot_cache.dart';

/// Local-first repository.
///
/// * Starts from the cached house (instant, works offline), then syncs with
///   the cloud in the background.
/// * Discovers devices on the LAN and keeps a live connection to each one;
///   every change a device reports is pushed to the UI immediately.
/// * Commands go over the LAN; if a device is not reachable locally (or
///   does not answer in time) they go through the cloud instead.
class HybridRepository implements HomeRepository {
  HybridRepository({
    required this.cloud,
    required this.cache,
    this.transport,
    this.localCommandTimeout = const Duration(seconds: 2),
    this.persistDelay = const Duration(seconds: 5),
  });

  final HomeRepository cloud;
  final SnapshotCache cache;

  /// Null on platforms without sockets (web preview): cloud only.
  final LocalTransport? transport;
  final Duration localCommandTimeout;
  final Duration persistDelay;

  HomeSnapshot? _snapshot;
  Map<String, LocalDeviceInfo> _infos = {};
  final Map<String, List<Channel>> _byDevice = {};
  final Map<String, LocalLink> _links = {};
  final List<StreamSubscription<Object?>> _subs = [];
  final _pushes = StreamController<List<Channel>>.broadcast();
  final _snapshots = StreamController<HomeSnapshot>.broadcast();
  bool _locating = false;
  Timer? _persist;

  @override
  Stream<List<Channel>> get pushes => _pushes.stream;

  @override
  Stream<HomeSnapshot> get snapshots => _snapshots.stream;

  /// Devices currently reachable on the LAN (for diagnostics).
  int get localCount => _links.values.where((l) => l.isConnected).length;

  /// Devices in this home that could be controlled locally.
  int get localTotal => _infos.length;

  @override
  Future<HomeSnapshot> load() async {
    final cached = await cache.read();
    if (cached != null) {
      _adopt(cached);
      unawaited(_syncCloud());
      return cached;
    }
    final fresh = await cloud.load();
    _adopt(fresh);
    await cache.write(fresh);
    return fresh;
  }

  Future<void> _syncCloud() async {
    try {
      final fresh = await cloud.load();
      final merged = _withKnownAddresses(fresh);
      _adopt(merged);
      await cache.write(merged);
      if (!_snapshots.isClosed) _snapshots.add(merged);
    } on Object {
      // Offline: keep running from the cache and the LAN.
    }
  }

  /// Keeps IPs/versions learnt on the LAN when the cloud sends new keys.
  HomeSnapshot _withKnownAddresses(HomeSnapshot s) => HomeSnapshot(
    homeName: s.homeName,
    rooms: s.rooms,
    channels: s.channels,
    scenes: s.scenes,
    localDevices: {
      for (final d in s.localDevices.values)
        d.id: d.copyWith(ip: _infos[d.id]?.ip, version: _infos[d.id]?.version),
    },
  );

  void _adopt(HomeSnapshot s) {
    _snapshot = s;
    _byDevice.clear();
    for (final c in s.channels) {
      (_byDevice[c.deviceId] ??= []).add(c);
    }
    // A key changed (device re-paired): reconnect with the new one.
    for (final d in s.localDevices.values) {
      final old = _infos[d.id];
      if (old != null && old.localKey != d.localKey) {
        unawaited(_links.remove(d.id)?.dispose());
      }
    }
    _infos = Map.of(s.localDevices);

    final t = transport;
    if (t == null) return;
    for (final info in _infos.values) {
      if (info.ip != null) _ensureLink(info);
    }
    if (!_locating) {
      _locating = true;
      _subs.add(t.locator.devices.listen(_onDiscovered));
      unawaited(t.locator.start());
    }
  }

  void _onDiscovered(DiscoveredDevice d) {
    final info = _infos[d.id];
    if (info == null) return; // Not part of this home.
    final updated = info.copyWith(ip: d.ip, version: d.version?.label);
    _infos[d.id] = updated;
    _ensureLink(updated);
    if (info.ip != d.ip || info.version != updated.version) _schedulePersist();
  }

  void _ensureLink(LocalDeviceInfo info) {
    final t = transport;
    final ip = info.ip;
    if (t == null || ip == null) return;
    final existing = _links[info.id];
    if (existing != null) {
      existing.updateIp(ip);
      return;
    }
    final link = t.linkFactory(
      deviceId: info.id,
      localKey: info.localKey,
      ip: ip,
      version: TuyaVersion.parse(info.version) ?? TuyaVersion.v33,
    );
    _links[info.id] = link;
    _subs
      ..add(link.updates.listen((dps) => _onDps(info.id, dps)))
      ..add(
        link.states.listen((s) {
          if (s == LinkState.connected) _onDps(info.id, link.dps);
        }),
      );
    unawaited(link.connect());
  }

  void _onDps(String deviceId, Map<String, Object?> dps) {
    final channels = _byDevice[deviceId];
    if (channels == null || dps.isEmpty) return;
    final changed = <Channel>[];
    for (final (i, c) in channels.indexed) {
      final v = dps[c.dp];
      if (v is bool) {
        final next = c.copyWith(isOn: v, online: true);
        channels[i] = next;
        changed.add(next);
      }
    }
    if (changed.isNotEmpty && !_pushes.isClosed) _pushes.add(changed);
  }

  void _schedulePersist() {
    _persist?.cancel();
    _persist = Timer(persistDelay, () {
      final s = _snapshot;
      if (s == null) return;
      unawaited(
        cache.write(
          HomeSnapshot(
            homeName: s.homeName,
            rooms: s.rooms,
            channels: [for (final list in _byDevice.values) ...list],
            scenes: s.scenes,
            localDevices: _infos,
          ),
        ),
      );
    });
  }

  @override
  Future<void> setChannel(Channel channel, bool on) async {
    final link = _links[channel.deviceId];
    final dp = channel.dp;
    if (link != null && link.isConnected && dp != null) {
      try {
        await link.set({dp: on}).timeout(localCommandTimeout);
        return;
      } on Object {
        // Fall through to the cloud.
      }
    }
    await cloud.setChannel(channel, on);
  }

  @override
  Future<List<Channel>> refresh(List<Channel> current) async {
    final local = <Channel>[];
    final remote = <Channel>[];
    for (final c in current) {
      final link = _links[c.deviceId];
      final v = link != null && link.isConnected ? link.dps[c.dp] : null;
      if (v is bool) {
        local.add(c.copyWith(isOn: v, online: true));
      } else {
        remote.add(c);
      }
    }
    if (remote.isEmpty) return local;
    try {
      return [...local, ...await cloud.refresh(remote)];
    } on Object {
      return [...local, ...remote];
    }
  }

  Future<void> dispose() async {
    _persist?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    for (final l in _links.values) {
      await l.dispose();
    }
    await transport?.locator.stop();
    await _pushes.close();
    await _snapshots.close();
  }
}
