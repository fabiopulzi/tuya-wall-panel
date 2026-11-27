// Read-only LAN check: discovers devices, connects to each one with its
// local key and reads its data points, then compares with the cloud.
// Sends no control commands.
//
//   dart run tool/local_status.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tuya_wall_panel/tuya/local/tuya_device_connection.dart';
import 'package:tuya_wall_panel/tuya/local/tuya_discovery.dart';
import 'package:tuya_wall_panel/tuya/local/tuya_protocol.dart';
import 'package:tuya_wall_panel/tuya/tuya_cloud_client.dart';

Future<void> main() async {
  final cfg = jsonDecode(
    File('tuya_credentials.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cloud = TuyaCloudClient(
    accessId: cfg['TUYA_ACCESS_ID'] as String,
    accessSecret: cfg['TUYA_ACCESS_SECRET'] as String,
    baseUrl: 'https://openapi.tuya${cfg['TUYA_REGION'] ?? 'us'}.com',
  );

  stdout.writeln('Buscando chaves locais na nuvem...');
  final info = <String, Map<String, dynamic>>{};
  for (final d in await cloud.projectDevices()) {
    info[d['id'] as String] = await cloud.device(d['id'] as String);
  }

  stdout.writeln('Escutando a rede por 12 s...');
  final found = await TuyaDiscovery.scan(window: const Duration(seconds: 12));
  stdout.writeln('${found.length} na rede\n');

  var ok = 0, failed = 0, mismatched = 0;
  final sw = Stopwatch()..start();
  await Future.wait([
    for (final d in found.values)
      if (info[d.id] case final i?)
        () async {
          final conn = TuyaDeviceConnection(
            deviceId: d.id,
            localKey: i['local_key'] as String,
            ip: d.ip,
            version: d.version ?? TuyaVersion.v33,
          );
          final t = Stopwatch()..start();
          try {
            final connected = conn.states
                .firstWhere((s) => s == LinkState.connected)
                .timeout(const Duration(seconds: 6));
            unawaited(conn.connect());
            await connected;
            final dps = await conn.refresh();
            final cloudSw = {
              for (final s in (i['status'] as List).cast<Map>())
                if ('${s['code']}'.startsWith('switch_') && s['value'] is bool)
                  '${s['code']}'.substring(7): s['value'],
            };
            final diff = [
              for (final MapEntry(:key, :value) in cloudSw.entries)
                if (dps[key] != value) 'dp$key local=${dps[key]} nuvem=$value',
            ];
            if (diff.isNotEmpty) mismatched++;
            ok++;
            final switches = {
              for (final e in dps.entries)
                if (e.value is bool) e.key: e.value,
            };
            stdout.writeln(
              '  ✓ ${(i['name'] as String).padRight(36)} ${d.ip.padRight(15)} '
              '${t.elapsedMilliseconds.toString().padLeft(4)} ms  $switches'
              '${diff.isEmpty ? '' : '  ≠ ${diff.join(', ')}'}',
            );
          } on Object catch (e) {
            failed++;
            stdout.writeln(
              '  ✗ ${(i['name'] as String).padRight(36)} ${d.ip}  $e',
            );
          } finally {
            await conn.dispose();
          }
        }(),
  ]);
  stdout.writeln(
    '\n$ok lidos, $failed falharam, $mismatched diferentes da nuvem '
    '(${sw.elapsedMilliseconds} ms no total)',
  );
  exit(0);
}
