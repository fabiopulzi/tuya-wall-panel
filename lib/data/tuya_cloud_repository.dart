import '../models/models.dart';
import '../tuya/tuya_cloud_client.dart';
import 'home_repository.dart';

/// Builds the house from the Tuya Cloud: homes, rooms and devices exactly as
/// they are organised in the Smart Life app, with one [Channel] per switch.
///
/// When the Smart Life account has several homes, [homeName] picks one;
/// otherwise the first home the linked account owns is used.
class TuyaCloudRepository implements HomeRepository {
  TuyaCloudRepository(this.client, {this.homeName});

  final TuyaCloudClient client;
  final String? homeName;

  static final _switchCode = RegExp(r'^(switch(_\d+)?|switch_led(_\d+)?)$');
  static final _pumpName = RegExp(
    r'piscina|bomba|filtro|pool|pump',
    caseSensitive: false,
  );
  static final _plugName = RegExp(r'tomada|plug|socket', caseSensitive: false);

  @override
  Future<HomeSnapshot> load() async {
    final devices = await client.projectDevices();
    if (devices.isEmpty) {
      return const HomeSnapshot(homeName: 'Casa', rooms: [], channels: []);
    }

    // The app-user uid is only on the v1 device detail, not the v2 list.
    final uid =
        (await client.device(devices.first['id'] as String))['uid'] as String;
    final (home, homeDevices) = await _pickHome(await client.homes(uid));
    final homeId = (home['home_id'] as num).toInt();
    devices.retainWhere((d) => homeDevices.contains(d['id']));

    final roomList = await client.rooms(homeId);
    final rooms = [
      for (final r in roomList)
        Room(id: '${r['room_id']}', name: r['name'] as String),
    ];
    final roomOf = <String, String>{};
    final roomDevices = await _pooled(
      roomList,
      (r) => client.roomDevices(homeId, (r['room_id'] as num).toInt()),
    );
    for (final (i, list) in roomDevices.indexed) {
      for (final d in list) {
        roomOf[d['id'] as String] = rooms[i].id;
      }
    }

    const unassigned = Room(id: '_none', name: 'Outros');
    final roomNames = {for (final r in rooms) r.id: r.name};

    Future<List<Channel>> channelsOf(Map<String, dynamic> summary) async {
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
      if (switches.isEmpty) return const [];

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
      return [
        for (final (i, s) in switches.indexed)
          Channel(
            deviceId: id,
            code: s['code'] as String,
            name: channelName(
              deviceName: deviceName,
              roomName: roomNames[roomOf[id]] ?? '',
              gangName: gangNames[s['code']],
              gang: switches.length > 1 ? i + 1 : null,
            ),
            kind: kind,
            roomId: roomOf[id] ?? unassigned.id,
            isOn: s['value'] as bool,
            online: info['online'] as bool? ?? true,
          ),
      ];
    }

    final channels = [
      for (final list in await _pooled(devices, channelsOf)) ...list,
    ];

    // Rooms with nothing controllable (e.g. an empty "Escada") are hidden.
    rooms.retainWhere((r) => channels.any((c) => c.roomId == r.id));
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
    final ids = {for (final c in current) c.deviceId}.toList();
    final statuses = await client.batchStatus(ids);
    return [
      for (final c in current)
        switch (statuses[c.deviceId]) {
          // Missing from the reply: the cloud has no live state for it.
          null => c,
          final status => switch (status
              .where((s) => s['code'] == c.code)
              .firstOrNull?['value']) {
            final bool v => c.copyWith(isOn: v),
            _ => c,
          },
        },
    ];
  }

  /// Runs [task] over [items] with at most [concurrency] requests in flight,
  /// keeping the input order. Tuya rate-limits bursts, so this stays small.
  Future<List<R>> _pooled<T, R>(
    List<T> items,
    Future<R> Function(T) task, {
    int concurrency = 6,
  }) async {
    final results = List<R?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final i = next++;
        results[i] = await task(items[i]);
      }
    }

    await Future.wait([for (var w = 0; w < concurrency; w++) worker()]);
    return results.cast<R>();
  }

  Future<(Map<String, dynamic>, Set<String>)> _pickHome(
    List<Map<String, dynamic>> homes,
  ) async {
    final wanted = homeName?.trim().toLowerCase();
    final ordered = [
      ...homes.where((h) => (h['name'] as String?)?.toLowerCase() == wanted),
      ...homes.where((h) => (h['name'] as String?)?.toLowerCase() != wanted),
    ];
    Object? lastError;
    for (final h in ordered) {
      try {
        return (h, await client.homeDeviceIds((h['home_id'] as num).toInt()));
      } on TuyaApiException catch (e) {
        lastError = e; // Shared homes deny access; try the next one.
      }
    }
    throw lastError ?? StateError('Nenhuma casa encontrada na conta Tuya');
  }

  /// Most Tuya relays (`kg`, `tdq`, `pc`) drive lights in practice, so the
  /// name decides: "Motor Piscina" is a pump, "Tomada ..." is a plug.
  DeviceKind _kindFor(String? category, String name) {
    if (_pumpName.hasMatch(name)) return DeviceKind.pump;
    if (category == 'cz' || _plugName.hasMatch(name)) return DeviceKind.plug;
    return DeviceKind.light;
  }
}

final _genericGang = RegExp(
  r'^(botão|botao|switch|button|tecla|interruptor|开关)\s*\d*$',
  caseSensitive: false,
);
final _separators = RegExp(r'(\s*[-–·/|]\s*)+');

/// A short, human name for one output.
///
/// Smart Life names are long ("Interruptor Quarto Caua - Entrada") and gangs
/// often keep their factory names ("Botão 2"). Inside a room card the room
/// is already known, so it is stripped: that example becomes "Entrada".
String channelName({
  required String deviceName,
  required String roomName,
  String? gangName,
  int? gang,
}) {
  if (gangName != null && !_genericGang.hasMatch(gangName.trim())) {
    return gangName.trim();
  }

  var base = deviceName.replaceFirst(
    RegExp(r'^\s*interruptor\b', caseSensitive: false),
    '',
  );
  if (roomName.isNotEmpty) {
    final plainRoom = _fold(roomName);
    final plainBase = _fold(base);
    final at = plainBase.indexOf(plainRoom);
    // _fold keeps string length, so indexes map back to the original.
    if (at >= 0) {
      base = base.replaceRange(at, at + roomName.length, ' ');
    }
  }
  base = base
      .replaceAll(_separators, ' - ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s-]+|[\s-]+$'), '')
      .trim();
  if (RegExp(r'^\d+$').hasMatch(base)) base = 'Painel $base';
  if (base.isNotEmpty) base = base[0].toUpperCase() + base.substring(1);

  if (gang == null) return base.isEmpty ? 'Luz' : base;
  return base.isEmpty ? 'Tecla $gang' : '$base · tecla $gang';
}

/// Lowercase and strip Portuguese accents, preserving length.
String _fold(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final out = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString();
}
