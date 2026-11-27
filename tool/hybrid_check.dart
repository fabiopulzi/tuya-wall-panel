// Runs the app's real data stack (cloud + LAN discovery + local links)
// without the UI and reports what it sees. Read-only: sends no commands.
//
//   dart run tool/hybrid_check.dart [seconds]
import 'dart:convert';
import 'dart:io';

import 'package:tuya_wall_panel/data/hybrid_repository.dart';
import 'package:tuya_wall_panel/data/snapshot_cache.dart';
import 'package:tuya_wall_panel/data/tuya_cloud_repository.dart';
import 'package:tuya_wall_panel/tuya/local/platform_local.dart';
import 'package:tuya_wall_panel/tuya/tuya_cloud_client.dart';

Future<void> main(List<String> args) async {
  final seconds = args.isEmpty ? 20 : int.parse(args.first);
  final cfg = jsonDecode(
    File('tuya_credentials.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cloud = TuyaCloudRepository(
    TuyaCloudClient(
      accessId: cfg['TUYA_ACCESS_ID'] as String,
      accessSecret: cfg['TUYA_ACCESS_SECRET'] as String,
      baseUrl: 'https://openapi.tuya${cfg['TUYA_REGION'] ?? 'us'}.com',
    ),
  );
  final cache = MemorySnapshotCache();
  final repo = HybridRepository(
    cloud: cloud,
    cache: cache,
    transport: createLocalTransport(),
  );

  final sw = Stopwatch()..start();
  final snap = await repo.load();
  stdout.writeln(
    'Casa "${snap.homeName}": ${snap.channels.length} canais, '
    '${snap.localDevices.length} chaves locais (${sw.elapsedMilliseconds} ms)',
  );
  var pushes = 0;
  repo.pushes.listen((list) => pushes += list.length);

  for (var t = 0; t < seconds; t += 5) {
    await Future<void>.delayed(const Duration(seconds: 5));
    stdout.writeln('  ${t + 5}s: ${repo.localCount} conectados na rede local');
  }

  final r = Stopwatch()..start();
  final fresh = await repo.refresh(snap.channels);
  final diff = [
    for (final (i, c) in fresh.indexed)
      if (c.isOn != snap.channels[i].isOn) c.name,
  ];
  stdout.writeln(
    'refresh: ${fresh.length} canais em ${r.elapsedMilliseconds} ms · '
    'avisos recebidos: $pushes · diferenças vs nuvem: '
    '${diff.isEmpty ? 'nenhuma' : diff.join(', ')}',
  );
  final ips = cache.value?.localDevices.values.where((d) => d.ip != null);
  stdout.writeln('IPs guardados no cache: ${ips?.length ?? 0}');
  await repo.dispose();
  exit(0);
}
