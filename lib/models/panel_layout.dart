import 'dart:convert';

import 'models.dart';

/// How the panel presents the house, set up on the tablet itself.
///
/// The Smart Life app stays untouched: this only decides which keys show on
/// the panel, in which room and order, and under which name. Keys wired in
/// parallel (two buttons for the same lamp) can be hidden so each lamp
/// appears once.
///
/// Every key is either in exactly one room or hidden. Keys that appear later
/// (a new device paired in Smart Life) are not lost: [normalized] places
/// them in their Smart Life room when it is still on the panel, otherwise in
/// a "Novos" room.
class PanelLayout {
  PanelLayout({
    required this.rooms,
    Iterable<String> hidden = const [],
    this.names = const {},
    this.allOff = const {},
    this.actions = const [],
  }) : hidden = {...hidden};

  /// Rooms in display order; each lists its visible keys in display order.
  final List<LayoutRoom> rooms;

  /// Keys left out of the panel.
  final Set<String> hidden;

  /// Panel-only names, by channel id.
  final Map<String, String> names;

  /// Who "Apagar tudo" turns off, where it differs from the default (lights
  /// yes, sockets and pumps no). A pool pump on a timer stays out.
  final Map<String, bool> allOff;

  /// Actions created on the tablet ("Hora do jantar", "Hora do filme"), in
  /// display order. "Apagar tudo" is not one of them: it is fixed, lives in
  /// the header and is configured through [allOff].
  final List<PanelAction> actions;

  static const newRoomId = '_new';

  /// The layout the panel shows when nothing was customized: the Smart Life
  /// rooms with every key, in Smart Life order.
  factory PanelLayout.fromHome(List<Room> rooms, List<Channel> channels) =>
      PanelLayout(
        rooms: [
          for (final r in rooms)
            LayoutRoom(
              id: r.id,
              name: r.name,
              icon: r.icon,
              channelIds: [
                for (final c in channels)
                  if (c.roomId == r.id) c.id,
              ],
            ),
        ],
      );

  /// Room that shows [channelId], or null when hidden / unknown.
  String? roomOf(String channelId) {
    for (final r in rooms) {
      if (r.channelIds.contains(channelId)) return r.id;
    }
    return null;
  }

  LayoutRoom? room(String id) {
    for (final r in rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  PanelLayout _copy({
    List<LayoutRoom>? rooms,
    Iterable<String>? hidden,
    Map<String, String>? names,
    Map<String, bool>? allOff,
    List<PanelAction>? actions,
  }) => PanelLayout(
    rooms: rooms ?? this.rooms,
    hidden: hidden ?? this.hidden,
    names: names ?? this.names,
    allOff: allOff ?? this.allOff,
    actions: actions ?? this.actions,
  );

  PanelAction? action(String id) {
    for (final a in actions) {
      if (a.id == id) return a;
    }
    return null;
  }

  PanelLayout addAction(PanelAction action) =>
      _copy(actions: [...actions, action]);

  PanelLayout updateAction(String id, {String? name, String? icon}) => _copy(
    actions: [
      for (final a in actions)
        if (a.id == id) a.copyWith(name: name?.trim(), icon: icon) else a,
    ],
  );

  PanelLayout removeAction(String id) => _copy(
    actions: [
      for (final a in actions)
        if (a.id != id) a,
    ],
  );

  /// Moves the action at [oldIndex] so it ends up at [newIndex].
  PanelLayout reorderActions(int oldIndex, int newIndex) {
    final next = [...actions];
    final a = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), a);
    return _copy(actions: next);
  }

  /// What an action does to a key: true turns it on, false off, null leaves
  /// it alone.
  PanelLayout setActionState(String actionId, String channelId, bool? state) =>
      _copy(
        actions: [
          for (final a in actions)
            if (a.id == actionId)
              a.copyWith(
                states: {
                  for (final MapEntry(:key, :value) in a.states.entries)
                    if (key != channelId) key: value,
                  channelId: ?state,
                },
              )
            else
              a,
        ],
      );

  /// Whether "Apagar tudo" turns [c] off.
  bool inAllOff(Channel c) => allOff[c.id] ?? c.kind == DeviceKind.light;

  /// Sets whether "Apagar tudo" turns [c] off; the default is not stored.
  PanelLayout setAllOff(Channel c, bool on) => _copy(
    allOff: {
      for (final MapEntry(:key, :value) in allOff.entries)
        if (key != c.id) key: value,
      if (on != (c.kind == DeviceKind.light)) c.id: on,
    },
  );

  /// Back to "lights only".
  PanelLayout resetAllOff() => _copy(allOff: const {});

  /// Moves a key into [toRoom] at [index] (end when null), or hides it when
  /// [toRoom] is null.
  PanelLayout moveChannel(String channelId, {String? toRoom, int? index}) {
    var target = index;
    final from = roomOf(channelId);
    if (from != null && from == toRoom && target != null) {
      final old = room(from)!.channelIds.indexOf(channelId);
      if (old < target) target -= 1;
    }
    final next = [
      for (final r in rooms)
        r.copyWith(
          channelIds: [
            for (final id in r.channelIds)
              if (id != channelId) id,
          ],
        ),
    ];
    final hidden = {...this.hidden}..remove(channelId);
    if (toRoom == null) {
      hidden.add(channelId);
    } else {
      final i = next.indexWhere((r) => r.id == toRoom);
      if (i < 0) return this;
      final ids = [...next[i].channelIds];
      ids.insert((target ?? ids.length).clamp(0, ids.length), channelId);
      next[i] = next[i].copyWith(channelIds: ids);
    }
    return _copy(rooms: next, hidden: hidden);
  }

  /// Sets a panel-only name; null or blank goes back to the original.
  PanelLayout renameChannel(String channelId, String? name) {
    final names = {...this.names};
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      names.remove(channelId);
    } else {
      names[channelId] = trimmed;
    }
    return _copy(names: names);
  }

  PanelLayout updateRoom(String roomId, {String? name, String? icon}) => _copy(
    rooms: [
      for (final r in rooms)
        if (r.id == roomId) r.copyWith(name: name?.trim(), icon: icon) else r,
    ],
  );

  PanelLayout addRoom(LayoutRoom room) => _copy(rooms: [...rooms, room]);

  /// Removes a room; its keys go to the hidden list so nothing is lost.
  PanelLayout removeRoom(String roomId) {
    final removed = room(roomId);
    if (removed == null) return this;
    return _copy(
      rooms: [
        for (final r in rooms)
          if (r.id != roomId) r,
      ],
      hidden: {...hidden, ...removed.channelIds},
    );
  }

  /// Moves the room at [oldIndex] so it ends up at [newIndex].
  PanelLayout reorderRooms(int oldIndex, int newIndex) {
    final next = [...rooms];
    final r = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), r);
    return _copy(rooms: next);
  }

  /// Drops keys that no longer exist and places keys the layout has never
  /// seen (see class docs).
  PanelLayout normalized(List<Channel> channels) {
    final known = {for (final c in channels) c.id};
    final placed = <String>{};
    final next = [
      for (final r in rooms)
        r.copyWith(
          channelIds: [
            for (final id in r.channelIds)
              if (known.contains(id) && placed.add(id)) id,
          ],
        ),
    ];
    final orphans = <String>[];
    for (final c in channels) {
      if (placed.contains(c.id) || hidden.contains(c.id)) continue;
      final i = next.indexWhere((r) => r.id == c.roomId);
      if (i >= 0) {
        next[i] = next[i].copyWith(channelIds: [...next[i].channelIds, c.id]);
      } else {
        orphans.add(c.id);
      }
    }
    if (orphans.isNotEmpty) {
      final i = next.indexWhere((r) => r.id == newRoomId);
      if (i >= 0) {
        next[i] = next[i].copyWith(
          channelIds: [...next[i].channelIds, ...orphans],
        );
      } else {
        next.add(LayoutRoom(id: newRoomId, name: 'Novos', channelIds: orphans));
      }
    }
    return _copy(
      rooms: next,
      hidden: hidden.where(known.contains),
      names: {
        for (final MapEntry(:key, :value) in names.entries)
          if (known.contains(key)) key: value,
      },
      allOff: {
        for (final MapEntry(:key, :value) in allOff.entries)
          if (known.contains(key)) key: value,
      },
      actions: [
        for (final a in actions)
          a.copyWith(
            states: {
              for (final MapEntry(:key, :value) in a.states.entries)
                if (known.contains(key)) key: value,
            },
          ),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'v': 1,
    'rooms': [for (final r in rooms) r.toJson()],
    'hidden': [...hidden],
    'names': names,
    'allOff': allOff,
    'actions': [for (final a in actions) a.toJson()],
  };

  factory PanelLayout.fromJson(Map<String, Object?> j) => PanelLayout(
    rooms: [
      for (final r in j['rooms']! as List)
        LayoutRoom.fromJson((r as Map).cast()),
    ],
    hidden: [for (final h in (j['hidden'] as List?) ?? const []) h as String],
    names: ((j['names'] as Map?) ?? const {}).cast<String, String>(),
    allOff: ((j['allOff'] as Map?) ?? const {}).cast<String, bool>(),
    actions: [
      for (final a in (j['actions'] as List?) ?? const [])
        PanelAction.fromJson((a as Map).cast()),
    ],
  );

  String encode() => jsonEncode(toJson());

  static PanelLayout decode(String raw) =>
      PanelLayout.fromJson((jsonDecode(raw) as Map).cast());
}

class LayoutRoom {
  const LayoutRoom({
    required this.id,
    required this.name,
    this.icon,
    this.channelIds = const [],
  });

  final String id;
  final String name;
  final String? icon;
  final List<String> channelIds;

  LayoutRoom copyWith({String? name, String? icon, List<String>? channelIds}) =>
      LayoutRoom(
        id: id,
        name: (name == null || name.isEmpty) ? this.name : name,
        icon: icon ?? this.icon,
        channelIds: channelIds ?? this.channelIds,
      );

  Room toRoom() => Room(id: id, name: name, icon: icon);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'channels': channelIds,
  };

  factory LayoutRoom.fromJson(Map<String, Object?> j) => LayoutRoom(
    id: j['id']! as String,
    name: j['name']! as String,
    icon: j['icon'] as String?,
    channelIds: [
      for (final c in (j['channels'] as List?) ?? const []) c as String,
    ],
  );
}

/// A one-tap action on the panel: sets some keys on, some off, and leaves
/// the rest alone.
class PanelAction {
  const PanelAction({
    required this.id,
    required this.name,
    this.icon,
    this.states = const {},
  });

  final String id;
  final String name;

  /// Icon key (see `ui/room_icons.dart`); guessed from the name when null.
  final String? icon;

  /// Channel id → desired state. Keys not listed are left alone.
  final Map<String, bool> states;

  PanelAction copyWith({
    String? name,
    String? icon,
    Map<String, bool>? states,
  }) => PanelAction(
    id: id,
    name: (name == null || name.isEmpty) ? this.name : name,
    icon: icon ?? this.icon,
    states: states ?? this.states,
  );

  Scene toScene() =>
      Scene(id: id, name: name, icon: icon ?? '', actions: states);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'states': states,
  };

  factory PanelAction.fromJson(Map<String, Object?> j) => PanelAction(
    id: j['id']! as String,
    name: j['name']! as String,
    icon: j['icon'] as String?,
    states: ((j['states'] as Map?) ?? const {}).cast<String, bool>(),
  );
}

/// Where the panel keeps its layout. Separate from the house cache, which
/// the cloud overwrites on every sync.
abstract interface class LayoutStore {
  Future<PanelLayout?> read();

  /// Null clears the customization.
  Future<void> write(PanelLayout? layout);
}

class MemoryLayoutStore implements LayoutStore {
  MemoryLayoutStore([this.value]);
  PanelLayout? value;

  @override
  Future<PanelLayout?> read() async => value;

  @override
  Future<void> write(PanelLayout? layout) async => value = layout;
}
