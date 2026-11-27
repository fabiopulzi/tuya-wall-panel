import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuya_wall_panel/data/home_repository.dart';
import 'package:tuya_wall_panel/models/models.dart';
import 'package:tuya_wall_panel/state/home_controller.dart';

Channel _ch(String id, {bool on = true}) => Channel(
  deviceId: id,
  code: 'switch_1',
  name: id,
  kind: DeviceKind.light,
  roomId: 'cozinha',
  isOn: on,
);

/// A fake cloud. [links] mirrors parallel wiring: commanding a key also
/// flips the linked one. [cloudLag] delays when the cloud reports a change.
class FakeCloud implements HomeRepository {
  FakeCloud(List<Channel> channels, {this.links = const {}, this.cloudLag})
    : state = {for (final c in channels) c.id: c.isOn},
      _initial = channels;

  final List<Channel> _initial;
  final Map<String, bool> state;
  final Map<String, String> links;
  final Duration? cloudLag;
  bool failNext = false;
  Completer<void>? refreshGate;
  int refreshes = 0;

  @override
  Future<HomeSnapshot> load() async =>
      HomeSnapshot(homeName: 'Casa', rooms: const [], channels: _initial);

  @override
  Future<void> setChannel(Channel channel, bool on) async {
    if (failNext) {
      failNext = false;
      throw Exception('offline');
    }
    void apply() {
      state[channel.id] = on;
      if (links[channel.id] case final other?) state[other] = on;
    }

    if (cloudLag == null) {
      apply();
    } else {
      Timer(cloudLag!, apply);
    }
  }

  @override
  Future<List<Channel>> refresh(List<Channel> current) async {
    refreshes++;
    final snapshot = Map.of(state);
    if (refreshGate != null) await refreshGate!.future;
    return [for (final c in current) c.copyWith(isOn: snapshot[c.id])];
  }
}

void main() {
  const entrada = 'entrada:switch_1';
  const bt = 'bt:switch_1';

  HomeController controllerFor(FakeCloud cloud) => HomeController(
    cloud,
    refreshEvery: const Duration(minutes: 10), // keep polling out of the way
  );

  test('a key wired in parallel follows shortly after a command', () {
    fakeAsync((async) {
      final cloud = FakeCloud(
        [_ch('entrada'), _ch('bt')],
        links: {entrada: bt},
      );
      final c = controllerFor(cloud)..load();
      async.flushMicrotasks();

      c.set(c.channels.firstWhere((x) => x.id == entrada), false);
      async.flushMicrotasks();
      expect(c.channels.firstWhere((x) => x.id == bt).isOn, isTrue);

      async.elapse(const Duration(milliseconds: 1600));
      expect(c.channels.firstWhere((x) => x.id == entrada).isOn, isFalse);
      expect(c.channels.firstWhere((x) => x.id == bt).isOn, isFalse);
      c.dispose();
    });
  });

  test('a slow cloud does not flip the commanded key back', () {
    fakeAsync((async) {
      final cloud = FakeCloud([
        _ch('entrada'),
        _ch('bt'),
      ], cloudLag: const Duration(seconds: 2));
      final c = controllerFor(cloud)..load();
      async.flushMicrotasks();

      c.set(c.channels.firstWhere((x) => x.id == entrada), false);
      // First follow-up at 1.5 s still sees the old "on" value in the cloud.
      async.elapse(const Duration(milliseconds: 1600));
      expect(c.channels.firstWhere((x) => x.id == entrada).isOn, isFalse);

      async.elapse(const Duration(seconds: 5));
      expect(c.channels.firstWhere((x) => x.id == entrada).isOn, isFalse);
      c.dispose();
    });
  });

  test('a burst of commands schedules one set of follow-ups', () {
    fakeAsync((async) {
      final cloud = FakeCloud([_ch('a'), _ch('b'), _ch('c')]);
      final c = controllerFor(cloud)..load();
      async.flushMicrotasks();

      c.allLightsOff();
      async.elapse(const Duration(seconds: 5));
      expect(cloud.refreshes, 2);
      c.dispose();
    });
  });

  test('a failed command rolls back and reports', () {
    fakeAsync((async) {
      final cloud = FakeCloud([_ch('entrada')])..failNext = true;
      final c = controllerFor(cloud)..load();
      async.flushMicrotasks();

      c.set(c.channels.single, false);
      async.flushMicrotasks();
      expect(c.channels.single.isOn, isTrue);
      expect(c.failures.value, contains('entrada'));
      c.dispose();
    });
  });

  test('a tap during an in-flight refresh is not overwritten by it', () {
    fakeAsync((async) {
      final cloud = FakeCloud([_ch('entrada')]);
      final c = controllerFor(cloud)..load();
      async.flushMicrotasks();

      cloud.refreshGate = Completer();
      c.refreshNow(); // snapshot taken: entrada = on
      async.flushMicrotasks();
      c.set(c.channels.single, false);
      async.flushMicrotasks();
      cloud.refreshGate!.complete();
      async.flushMicrotasks();

      expect(c.channels.single.isOn, isFalse);
      c.dispose();
    });
  });
}
