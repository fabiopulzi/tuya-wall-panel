import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuya_wall_panel/data/home_repository.dart';
import 'package:tuya_wall_panel/data/hybrid_repository.dart';
import 'package:tuya_wall_panel/data/snapshot_cache.dart';
import 'package:tuya_wall_panel/models/models.dart';
import 'package:tuya_wall_panel/tuya/local/local_link.dart';
import 'package:tuya_wall_panel/tuya/local/tuya_protocol.dart';

const _room = Room(id: 'r', name: 'Cozinha');

Channel _ch(String dev, String dp, {bool on = false}) => Channel(
  deviceId: dev,
  code: 'switch_$dp',
  dp: dp,
  name: '$dev/$dp',
  kind: DeviceKind.light,
  roomId: 'r',
  isOn: on,
);

HomeSnapshot _snap({bool on = false, String name = 'Casa'}) => HomeSnapshot(
  homeName: name,
  rooms: const [_room],
  channels: [
    _ch('entrada', '1', on: on),
    _ch('bt', '1'),
    _ch('bt', '2'),
  ],
  localDevices: const {
    'entrada': LocalDeviceInfo(id: 'entrada', localKey: '0123456789abcdef'),
    'bt': LocalDeviceInfo(id: 'bt', localKey: 'fedcba9876543210'),
  },
);

class FakeCloud implements HomeRepository {
  FakeCloud({this.fail = false});
  bool fail;
  HomeSnapshot next = _snap(name: 'Nuvem');
  final List<(String, bool)> commands = [];
  int refreshed = 0;

  @override
  Future<HomeSnapshot> load() async => fail ? throw Exception('offline') : next;
  @override
  Future<void> setChannel(Channel c, bool on) async {
    if (fail) throw Exception('offline');
    commands.add((c.id, on));
  }

  @override
  Future<List<Channel>> refresh(List<Channel> current) async {
    refreshed += current.length;
    return [for (final c in current) c.copyWith(isOn: true)];
  }

  @override
  Stream<List<Channel>> get pushes => const Stream.empty();
  @override
  Stream<HomeSnapshot> get snapshots => const Stream.empty();
}

class FakeLink implements LocalLink {
  FakeLink(this.deviceId, this.ip);
  @override
  final String deviceId;
  String ip;
  bool connected = false;
  bool hang = false;
  final List<Map<String, Object?>> sent = [];
  final _updates = StreamController<Map<String, Object?>>.broadcast();
  final _states = StreamController<LinkState>.broadcast();

  @override
  final Map<String, Object?> dps = {};
  @override
  bool get isConnected => connected;
  @override
  Stream<Map<String, Object?>> get updates => _updates.stream;
  @override
  Stream<LinkState> get states => _states.stream;

  void goOnline(Map<String, Object?> values) {
    dps.addAll(values);
    connected = true;
    _states.add(LinkState.connected);
  }

  void push(Map<String, Object?> values) {
    dps.addAll(values);
    _updates.add(values);
  }

  @override
  Future<void> connect() async {}
  @override
  Future<void> set(Map<String, Object?> values) async {
    if (hang) await Completer<void>().future;
    sent.add(values);
  }

  @override
  void updateIp(String ip) => this.ip = ip;
  @override
  Future<void> dispose() async {}
}

class FakeLocator implements DeviceLocator {
  final _c = StreamController<DiscoveredDevice>.broadcast();
  void announce(String id, String ip) =>
      _c.add(DiscoveredDevice(id: id, ip: ip, version: TuyaVersion.v33));
  @override
  Stream<DiscoveredDevice> get devices => _c.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

void main() {
  late FakeCloud cloud;
  late MemorySnapshotCache cache;
  late FakeLocator locator;
  late Map<String, FakeLink> links;
  late HybridRepository repo;

  HybridRepository build() => HybridRepository(
    cloud: cloud,
    cache: cache,
    transport: LocalTransport(
      locator: locator,
      linkFactory: ({
        required deviceId,
        required localKey,
        required ip,
        required version,
      }) => links[deviceId] = FakeLink(deviceId, ip),
    ),
    localCommandTimeout: const Duration(milliseconds: 100),
    persistDelay: const Duration(milliseconds: 10),
  );

  setUp(() {
    cloud = FakeCloud();
    cache = MemorySnapshotCache();
    locator = FakeLocator();
    links = {};
    repo = build();
  });

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('first start loads the cloud and fills the cache', () async {
    final snap = await repo.load();
    expect(snap.homeName, 'Nuvem');
    expect(cache.value?.homeName, 'Nuvem');
  });

  test('later starts open from the cache, then publish the cloud', () async {
    cache.value = _snap(name: 'Cache');
    final published = repo.snapshots.first;
    expect((await repo.load()).homeName, 'Cache');
    expect((await published).homeName, 'Nuvem');
  });

  test('works offline from the cache', () async {
    cache.value = _snap(name: 'Cache');
    cloud.fail = true;
    expect((await repo.load()).homeName, 'Cache');
  });

  test('commands go over the LAN when the device is connected', () async {
    await repo.load();
    locator.announce('entrada', '10.0.0.105');
    await tick();
    links['entrada']!.goOnline({'1': false});

    await repo.setChannel(_ch('entrada', '1'), true);
    expect(links['entrada']!.sent, [
      {'1': true},
    ]);
    expect(cloud.commands, isEmpty);
  });

  test('falls back to the cloud when the device is not on the LAN', () async {
    await repo.load();
    await repo.setChannel(_ch('bt', '2'), true);
    expect(cloud.commands, [('bt:switch_2', true)]);
  });

  test('falls back to the cloud when the device does not answer', () async {
    await repo.load();
    locator.announce('entrada', '10.0.0.105');
    await tick();
    links['entrada']!
      ..goOnline({'1': false})
      ..hang = true;
    await repo.setChannel(_ch('entrada', '1'), true);
    expect(cloud.commands, [('entrada:switch_1', true)]);
  });

  test('a parallel key changing on the device is pushed at once', () async {
    await repo.load();
    locator.announce('bt', '10.0.0.108');
    await tick();
    links['bt']!.goOnline({'1': true, '2': true});
    await tick(); // let the "connected" sync go out first

    final pushed = repo.pushes.first;
    links['bt']!.push({'1': false, '16': true});
    final channels = await pushed;
    expect(channels.map((c) => (c.id, c.isOn)), [('bt:switch_1', false)]);
  });

  test(
    'refresh reads connected devices locally, the rest from the cloud',
    () async {
      await repo.load();
      locator.announce('entrada', '10.0.0.105');
      await tick();
      links['entrada']!.goOnline({'1': false});

      final fresh = await repo.refresh(_snap().channels);
      expect(cloud.refreshed, 2); // only the two "bt" channels
      expect(fresh.firstWhere((c) => c.deviceId == 'entrada').isOn, isFalse);
    },
  );

  test('learnt IPs are saved for the next start', () async {
    await repo.load();
    locator.announce('entrada', '10.0.0.105');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cache.value!.localDevices['entrada']!.ip, '10.0.0.105');
  });

  test('the cache keeps names, dp ids, keys, IPs and offline flags', () {
    final original = HomeSnapshot(
      homeName: 'Casa',
      rooms: const [_room],
      channels: [_ch('bt', '2', on: true).copyWith(online: false)],
      localDevices: const {
        'bt': LocalDeviceInfo(
          id: 'bt',
          localKey: 'fedcba9876543210',
          ip: '10.0.0.108',
          version: '3.3',
        ),
      },
    );
    final back = decodeSnapshot(encodeSnapshot(original));
    final c = back.channels.single;
    expect((c.id, c.dp, c.isOn, c.online), ('bt:switch_2', '2', true, false));
    expect(back.localDevices['bt']!.ip, '10.0.0.108');
    expect(back.rooms.single.name, 'Cozinha');
  });

  test('devices from other homes are ignored', () async {
    await repo.load();
    locator.announce('vizinho', '10.0.0.200');
    await tick();
    expect(links, isNot(contains('vizinho')));
  });
}
