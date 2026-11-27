// Sends one switch command through the app's Tuya client and reads the
// state back.
//
//   dart run tool/set_switch.dart <device_id> <on|off> [code=switch_1]
import 'dart:convert';
import 'dart:io';

import 'package:tuya_wall_panel/tuya/tuya_cloud_client.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'uso: dart run tool/set_switch.dart <device_id> <on|off> [code]',
    );
    exit(64);
  }
  final cfg = jsonDecode(
    File('tuya_credentials.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final client = TuyaCloudClient(
    accessId: cfg['TUYA_ACCESS_ID'] as String,
    accessSecret: cfg['TUYA_ACCESS_SECRET'] as String,
    baseUrl: 'https://openapi.tuya${cfg['TUYA_REGION'] ?? 'us'}.com',
  );
  final id = args[0];
  final on = args[1] == 'on';
  final code = args.length > 2 ? args[2] : 'switch_1';

  Future<Object?> read() async =>
      (await client.status(id)).firstWhere((s) => s['code'] == code)['value'];

  stdout.writeln('antes:  $code = ${await read()}');
  final sw = Stopwatch()..start();
  await client.sendCommand(id, code, on);
  stdout.writeln('comando enviado em ${sw.elapsedMilliseconds} ms');
  await Future<void>.delayed(const Duration(seconds: 2));
  stdout.writeln('depois: $code = ${await read()}');
  exit(0);
}
