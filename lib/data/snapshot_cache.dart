import 'dart:convert';

import '../models/models.dart';

/// Persists the last known house on the tablet so the panel opens instantly
/// and keeps working on the LAN when the internet (or the Tuya cloud) is
/// down.
abstract interface class SnapshotCache {
  Future<HomeSnapshot?> read();
  Future<void> write(HomeSnapshot snapshot);
}

class MemorySnapshotCache implements SnapshotCache {
  HomeSnapshot? value;
  @override
  Future<HomeSnapshot?> read() async => value;
  @override
  Future<void> write(HomeSnapshot snapshot) async => value = snapshot;
}

String encodeSnapshot(HomeSnapshot s) => jsonEncode({
  'homeName': s.homeName,
  'rooms': [
    for (final r in s.rooms) {'id': r.id, 'name': r.name, 'icon': r.icon},
  ],
  'channels': [
    for (final c in s.channels)
      {
        'deviceId': c.deviceId,
        'code': c.code,
        'dp': c.dp,
        'name': c.name,
        'kind': c.kind.name,
        'roomId': c.roomId,
        'isOn': c.isOn,
        'online': c.online,
      },
  ],
  'localDevices': [for (final d in s.localDevices.values) d.toJson()],
});

HomeSnapshot decodeSnapshot(String raw) {
  final j = jsonDecode(raw) as Map<String, Object?>;
  return HomeSnapshot(
    homeName: j['homeName']! as String,
    rooms: [
      for (final r in (j['rooms']! as List).cast<Map<String, Object?>>())
        Room(
          id: r['id']! as String,
          name: r['name']! as String,
          icon: r['icon'] as String?,
        ),
    ],
    channels: [
      for (final c in (j['channels']! as List).cast<Map<String, Object?>>())
        Channel(
          deviceId: c['deviceId']! as String,
          code: c['code']! as String,
          dp: c['dp'] as String?,
          name: c['name']! as String,
          kind: DeviceKind.values.byName(c['kind']! as String),
          roomId: c['roomId']! as String,
          isOn: c['isOn']! as bool,
          online: c['online'] as bool? ?? true,
        ),
    ],
    localDevices: {
      for (final d
          in (j['localDevices']! as List).cast<Map<String, Object?>>().map(
            LocalDeviceInfo.fromJson,
          ))
        d.id: d,
    },
  );
}
