import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuya_wall_panel/tuya/local/tuya_device_connection.dart';
import 'package:tuya_wall_panel/tuya/local/tuya_protocol.dart';

import 'support/fake_tuya_device.dart';

const _id = 'bf00000000000000test01';
const _key = 'a1b2c3d4e5f6g7h8';

Future<TuyaDeviceConnection> _connect(FakeTuyaDevice device) async {
  final conn = TuyaDeviceConnection(
    deviceId: _id,
    localKey: _key,
    ip: '127.0.0.1',
    port: device.port,
    version: device.version,
    requestTimeout: const Duration(seconds: 2),
  );
  await conn.connect().timeout(const Duration(seconds: 3));
  expect(conn.isConnected, isTrue, reason: 'should connect to the fake');
  return conn;
}

void main() {
  for (final version in TuyaVersion.values) {
    group('protocol ${version.label}', () {
      late FakeTuyaDevice device;
      late TuyaDeviceConnection conn;

      setUp(() async {
        device = FakeTuyaDevice(
          version: version,
          localKey: _key,
          deviceId: _id,
          dps: {'1': false, '2': true, '16': true},
        );
        await device.start();
        conn = await _connect(device);
      });

      tearDown(() async {
        await conn.dispose();
        await device.stop();
      });

      test('reads every data point after connecting', () async {
        expect(await conn.refresh(), {'1': false, '2': true, '16': true});
      });

      test(
        'a command reaches the device and comes back as an update',
        () async {
          final update = conn.updates.first;
          await conn.set({'1': true});
          expect(device.controls, [
            {'1': true},
          ]);
          expect(await update.timeout(const Duration(seconds: 2)), {'1': true});
          expect(conn.dps['1'], isTrue);
        },
      );

      test('pressing the wall switch is pushed without asking', () async {
        await conn.refresh();
        final update = conn.updates.first;
        device.press('2', false);
        expect(await update.timeout(const Duration(seconds: 2)), {'2': false});
      });
    });
  }

  test('a wrong local key fails the 3.4 handshake and retries later', () async {
    final device = FakeTuyaDevice(
      version: TuyaVersion.v34,
      localKey: _key,
      deviceId: _id,
    );
    await device.start();
    final conn = TuyaDeviceConnection(
      deviceId: _id,
      localKey: 'XXXXXXXXXXXXXXXX',
      ip: '127.0.0.1',
      port: device.port,
      version: TuyaVersion.v34,
      requestTimeout: const Duration(milliseconds: 500),
    );
    final states = <LinkState>[];
    conn.states.listen(states.add);
    await conn.connect();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(conn.isConnected, isFalse);
    expect(states.last, LinkState.disconnected);
    await conn.dispose();
    await device.stop();
  });

  test('a silent device times out instead of hanging', () async {
    final device = FakeTuyaDevice(
      version: TuyaVersion.v33,
      localKey: _key,
      deviceId: _id,
      silent: true,
    );
    await device.start();
    final conn = TuyaDeviceConnection(
      deviceId: _id,
      localKey: _key,
      ip: '127.0.0.1',
      port: device.port,
      version: TuyaVersion.v33,
      requestTimeout: const Duration(milliseconds: 300),
    );
    // connect() reads status, which times out and drops the link.
    await conn.connect();
    expect(conn.isConnected, isFalse);
    await expectLater(conn.set({'1': true}), throwsA(isA<SocketException>()));
    await conn.dispose();
    await device.stop();
  });

  test('reconnects after the device restarts', () async {
    final device = FakeTuyaDevice(
      version: TuyaVersion.v33,
      localKey: _key,
      deviceId: _id,
    );
    await device.start();
    final conn = await _connect(device);
    final port = device.port;
    await device.stop(); // power cut

    final down = conn.states.firstWhere((s) => s == LinkState.disconnected);
    await down.timeout(const Duration(seconds: 2));

    final again = FakeTuyaDevice(
      version: TuyaVersion.v33,
      localKey: _key,
      deviceId: _id,
    );
    await again.startOn(port);
    await conn.states
        .firstWhere((s) => s == LinkState.connected)
        .timeout(const Duration(seconds: 5));
    expect(await conn.refresh(), containsPair('1', false));
    await conn.dispose();
    await again.stop();
  });
}
