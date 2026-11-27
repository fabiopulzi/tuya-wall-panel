// Loads the house from the Tuya Cloud with the app's own repository and
// prints it, without starting the UI.
//
//   dart run tool/check_cloud.dart tuya_credentials.json
import 'dart:convert';
import 'dart:io';

import 'package:tuya_wall_panel/data/tuya_cloud_repository.dart';
import 'package:tuya_wall_panel/tuya/tuya_cloud_client.dart';

Future<void> main(List<String> args) async {
  final cfg = jsonDecode(
    File(args.isEmpty ? 'tuya_credentials.json' : args.first)
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final repo = TuyaCloudRepository(
    TuyaCloudClient(
      accessId: cfg['TUYA_ACCESS_ID'] as String,
      accessSecret: cfg['TUYA_ACCESS_SECRET'] as String,
      baseUrl: 'https://openapi.tuya${cfg['TUYA_REGION'] ?? 'us'}.com',
    ),
    homeName: cfg['TUYA_HOME'] as String?,
  );
  final snap = await repo.load();
  stdout.writeln('Casa: ${snap.homeName} · ${snap.channels.length} canais');
  for (final room in snap.rooms) {
    final chs = snap.channels.where((c) => c.roomId == room.id);
    stdout.writeln('\n${room.name} (${chs.length})');
    for (final c in chs) {
      stdout.writeln(
        '  ${c.isOn ? '●' : '○'} ${c.name.padRight(32)} '
        '${c.kind.name.padRight(6)} ${c.online ? '' : 'OFFLINE'}',
      );
    }
  }
  exit(0);
}
