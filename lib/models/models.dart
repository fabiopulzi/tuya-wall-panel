/// Domain model for the panel.
///
/// A Tuya *device* may expose several independent switches (a 3-gang wall
/// switch has `switch_1`, `switch_2`, `switch_3`). The UI works on
/// [Channel]s — one per controllable output — because that is what a person
/// thinks of as "a light".
library;

enum DeviceKind { light, plug, pump, other }

class Channel {
  const Channel({
    required this.deviceId,
    required this.code,
    required this.name,
    required this.kind,
    required this.roomId,
    this.isOn = false,
    this.online = true,
  });

  final String deviceId;

  /// Tuya data point code, e.g. `switch_1`, `switch_led`.
  final String code;
  final String name;
  final DeviceKind kind;
  final String roomId;
  final bool isOn;
  final bool online;

  String get id => '$deviceId:$code';

  Channel copyWith({bool? isOn, bool? online, String? name}) => Channel(
    deviceId: deviceId,
    code: code,
    name: name ?? this.name,
    kind: kind,
    roomId: roomId,
    isOn: isOn ?? this.isOn,
    online: online ?? this.online,
  );
}

class Room {
  const Room({required this.id, required this.name, this.icon});

  final String id;
  final String name;

  /// Optional icon key (see `ui/room_icons.dart`). When null the icon is
  /// guessed from the room name.
  final String? icon;
}

class Scene {
  const Scene({
    required this.id,
    required this.name,
    required this.icon,
    required this.actions,
  });

  final String id;
  final String name;
  final String icon;

  /// Channel id → desired state.
  final Map<String, bool> actions;
}

class HomeSnapshot {
  const HomeSnapshot({
    required this.homeName,
    required this.rooms,
    required this.channels,
    this.scenes = const [],
  });

  final String homeName;
  final List<Room> rooms;
  final List<Channel> channels;
  final List<Scene> scenes;
}
