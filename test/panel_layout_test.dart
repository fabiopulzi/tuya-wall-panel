import 'package:flutter_test/flutter_test.dart';
import 'package:tuya_wall_panel/data/home_repository.dart';
import 'package:tuya_wall_panel/models/models.dart';
import 'package:tuya_wall_panel/models/panel_layout.dart';
import 'package:tuya_wall_panel/state/home_controller.dart';

Channel _ch(String id, String room, {bool on = false}) => Channel(
  deviceId: id,
  code: 'switch_1',
  name: 'Original $id',
  kind: DeviceKind.light,
  roomId: room,
  isOn: on,
);

String _id(String dev) => '$dev:switch_1';

const _rooms = [
  Room(id: 'sala', name: 'Sala'),
  Room(id: 'cozinha', name: 'Cozinha'),
];

final _channels = [
  _ch('a', 'sala', on: true),
  _ch('b', 'sala', on: true), // parallel key of "a"
  _ch('c', 'cozinha'),
];

class _Repo implements HomeRepository {
  _Repo(this.channels);
  List<Channel> channels;
  final commands = <String>[];

  @override
  Future<HomeSnapshot> load() async =>
      HomeSnapshot(homeName: 'Casa', rooms: _rooms, channels: channels);
  @override
  Future<void> setChannel(Channel c, bool on) async => commands.add(c.id);
  @override
  Future<List<Channel>> refresh(List<Channel> current) async => current;
  @override
  Stream<List<Channel>> get pushes => const Stream.empty();
  @override
  Stream<HomeSnapshot> get snapshots => const Stream.empty();
}

void main() {
  group('PanelLayout', () {
    final base = PanelLayout.fromHome(_rooms, _channels);

    test('starts from the Smart Life rooms', () {
      expect(base.rooms.map((r) => '${r.id}=${r.channelIds.join(',')}'), [
        'sala=${_id('a')},${_id('b')}',
        'cozinha=${_id('c')}',
      ]);
    });

    test('moves, reorders, hides and shows keys', () {
      var l = base.moveChannel(_id('c'), toRoom: 'sala', index: 0);
      expect(l.room('sala')!.channelIds, [_id('c'), _id('a'), _id('b')]);
      expect(l.room('cozinha')!.channelIds, isEmpty);

      // Dragging "c" below "a" within the same room.
      l = l.moveChannel(_id('c'), toRoom: 'sala', index: 2);
      expect(l.room('sala')!.channelIds, [_id('a'), _id('c'), _id('b')]);

      l = l.moveChannel(_id('b'));
      expect(l.hidden, {_id('b')});
      expect(l.roomOf(_id('b')), isNull);

      l = l.moveChannel(_id('b'), toRoom: 'cozinha');
      expect(l.hidden, isEmpty);
      expect(l.room('cozinha')!.channelIds, [_id('b')]);
    });

    test('rooms can be added, renamed, reordered and removed', () {
      var l = base
          .addRoom(const LayoutRoom(id: 'u1', name: 'Varanda'))
          .updateRoom('sala', name: 'Living', icon: 'sofa')
          .reorderRooms(2, 0);
      expect(l.rooms.map((r) => r.name), ['Varanda', 'Living', 'Cozinha']);
      expect(l.room('sala')!.icon, 'sofa');

      l = l.removeRoom('sala');
      expect(l.rooms.map((r) => r.id), ['u1', 'cozinha']);
      expect(l.hidden, {_id('a'), _id('b')}, reason: 'keys are kept hidden');
    });

    test('names are panel-only and can go back to the original', () {
      final l = base.renameChannel(_id('a'), '  Lustre  ');
      expect(l.names, {_id('a'): 'Lustre'});
      expect(l.renameChannel(_id('a'), '').names, isEmpty);
    });

    test('new devices are placed, removed ones dropped', () {
      final l = base
          .removeRoom('cozinha')
          .moveChannel(_id('c'), toRoom: 'sala')
          .renameChannel(_id('a'), 'Lustre');
      final n = l.normalized([
        _ch('a', 'sala'),
        _ch('c', 'cozinha'),
        _ch('d', 'sala'), // new, its Smart Life room is on the panel
        _ch('e', 'garagem'), // new, unknown room
      ]);
      expect(n.room('sala')!.channelIds, [_id('a'), _id('c'), _id('d')]);
      expect(n.room(PanelLayout.newRoomId)!.channelIds, [_id('e')]);
      expect(n.hidden, isEmpty, reason: '"b" no longer exists');
    });

    test('survives a save and a new app version (JSON round trip)', () {
      final l = base
          .moveChannel(_id('b'))
          .renameChannel(_id('a'), 'Lustre')
          .updateRoom('sala', icon: 'sofa');
      final back = PanelLayout.decode(l.encode());
      expect(
        back.rooms.map((r) => '${r.id}|${r.name}|${r.icon}|${r.channelIds}'),
        ['sala|Sala|sofa|[${_id('a')}]', 'cozinha|Cozinha|null|[${_id('c')}]'],
      );
      expect(back.hidden, {_id('b')});
      expect(back.names, {_id('a'): 'Lustre'});
    });
  });

  group('HomeController with a layout', () {
    late _Repo repo;
    late MemoryLayoutStore store;
    late HomeController c;

    setUp(() async {
      repo = _Repo(_channels);
      store = MemoryLayoutStore();
      c = HomeController(repo, layouts: store);
      await c.load();
    });

    tearDown(() => c.dispose());

    test('without customization it shows Smart Life as is', () {
      expect(c.rooms.map((r) => r.name), ['Sala', 'Cozinha']);
      expect(c.channelsIn('sala').length, 2);
      expect(c.isCustomized, isFalse);
    });

    test('hidden keys leave the panel, counts and room actions', () async {
      await c.hideChannel(_id('b'));
      expect(c.channelsIn('sala').map((x) => x.id), [_id('a')]);
      expect(c.lightsOn, 1);
      await c.setRoomLights('sala', false);
      expect(repo.commands, [_id('a')]);
      expect(store.value!.hidden, {_id('b')});
    });

    test('offline keys are skipped by "Apagar tudo"', () async {
      repo.channels = [
        ..._channels,
        _ch('d', 'sala', on: true).copyWith(online: false),
      ];
      await c.load();
      await c.allLightsOff();
      expect(repo.commands, [_id('a'), _id('b')]);
      expect(c.failures.value, isNull);
    });

    test('panel names show on the panel only', () async {
      await c.renameChannel(_id('a'), 'Lustre');
      expect(c.channelsIn('sala').first.name, 'Lustre');
      expect(c.channel(_id('a'))!.name, 'Original a');
    });

    test('empty rooms are not shown', () async {
      await c.updateLayout(
        c.editableLayout.moveChannel(_id('c'), toRoom: 'sala'),
      );
      expect(c.rooms.map((r) => r.id), ['sala']);
    });

    test('the saved layout is used on the next start', () async {
      await c.renameChannel(_id('a'), 'Lustre');
      final next = HomeController(_Repo(_channels), layouts: store);
      await next.load();
      expect(next.channelsIn('sala').first.name, 'Lustre');
      next.dispose();
    });

    test('restoring goes back to Smart Life', () async {
      await c.hideChannel(_id('b'));
      await c.resetLayout();
      expect(c.channelsIn('sala').length, 2);
      expect(store.value, isNull);
    });
  });
}
