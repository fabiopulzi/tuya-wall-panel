import '../models/models.dart';
import '../tuya/tuya_cloud_client.dart';
import 'home_repository.dart';

/// Builds the house from the Tuya Cloud: homes, rooms and devices exactly as
/// they are organised in the Smart Life app, with one [Channel] per switch.
///
/// Not yet validated against a real account — the first run with real
/// credentials is the next milestone.
class TuyaCloudRepository implements HomeRepository {
  TuyaCloudRepository(this.client);

  final TuyaCloudClient client;

  static final _switchCode = RegExp(r'^(switch(_\d+)?|switch_led(_\d+)?)$');
  static final _pumpName = RegExp(
    r'piscina|bomba|filtro|pool|pump',
    caseSensitive: false,
  );

  @override
  Future<HomeSnapshot> load() async {
    final devices = await client.projectDevices();
    if (devices.isEmpty) {
      return const HomeSnapshot(homeName: 'Casa', rooms: [], channels: []);
    }

    // The app-user uid is on every linked device.
    final uid = devices.first['uid'] as String;
    final home = (await client.homes(uid)).first;
    final homeId = (home['home_id'] as num).toInt();

    final rooms = <Room>[];
    final roomOf = <String, String>{};
    for (final r in await client.rooms(homeId)) {
      final roomId = (r['room_id'] as num).toInt();
      rooms.add(Room(id: '$roomId', name: r['name'] as String));
      for (final d in await client.roomDevices(homeId, roomId)) {
        roomOf[d['id'] as String] = '$roomId';
      }
    }

    const unassigned = Room(id: '_none', name: 'Sem cômodo');
    final channels = <Channel>[];
    for (final summary in devices) {
      final id = summary['id'] as String;
      final info = await client.device(id);
      final status = (info['status'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final switches = status
          .where(
            (s) =>
                _switchCode.hasMatch(s['code'] as String) && s['value'] is bool,
          )
          .toList();
      if (switches.isEmpty) continue;

      final deviceName = info['name'] as String? ?? id;
      var gangNames = const <String, String>{};
      if (switches.length > 1) {
        try {
          gangNames = await client.subSwitchNames(id);
        } on Object {
          // Older devices don't support custom gang names.
        }
      }

      final kind = _kindFor(info['category'] as String?, deviceName);
      for (final (i, s) in switches.indexed) {
        final code = s['code'] as String;
        channels.add(
          Channel(
            deviceId: id,
            code: code,
            name:
                gangNames[code] ??
                (switches.length > 1 ? '$deviceName ${i + 1}' : deviceName),
            kind: kind,
            roomId: roomOf[id] ?? unassigned.id,
            isOn: s['value'] as bool,
            online: info['online'] as bool? ?? true,
          ),
        );
      }
    }

    if (channels.any((c) => c.roomId == unassigned.id)) rooms.add(unassigned);

    return HomeSnapshot(
      homeName: home['name'] as String? ?? 'Casa',
      rooms: rooms,
      channels: channels,
    );
  }

  @override
  Future<void> setChannel(Channel channel, bool on) =>
      client.sendCommand(channel.deviceId, channel.code, on);

  @override
  Future<List<Channel>> refresh(List<Channel> current) async {
    final byDevice = <String, List<Channel>>{};
    for (final c in current) {
      (byDevice[c.deviceId] ??= []).add(c);
    }
    final out = <Channel>[];
    for (final entry in byDevice.entries) {
      try {
        final status = {
          for (final s in await client.status(entry.key)) s['code']: s['value'],
        };
        out.addAll(
          entry.value.map((c) {
            final v = status[c.code];
            return v is bool ? c.copyWith(isOn: v, online: true) : c;
          }),
        );
      } on Object {
        out.addAll(entry.value.map((c) => c.copyWith(online: false)));
      }
    }
    return out;
  }

  DeviceKind _kindFor(String? category, String name) {
    if (_pumpName.hasMatch(name)) return DeviceKind.pump;
    return switch (category) {
      'kg' || 'dj' || 'tgkg' || 'tgq' || 'dd' => DeviceKind.light,
      'cz' || 'pc' || 'tdq' => DeviceKind.plug,
      _ => DeviceKind.other,
    };
  }
}
