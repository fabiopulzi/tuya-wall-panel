// Listens for Tuya UDP broadcasts on the local network.
//
//   dart run tool/scan_lan.dart [seconds]
import 'dart:io';

import 'package:tuya_wall_panel/tuya/local/tuya_discovery.dart';

Future<void> main(List<String> args) async {
  final seconds = args.isEmpty ? 15 : int.parse(args.first);
  stdout.writeln('Escutando broadcasts Tuya por $seconds s...');
  final found = await TuyaDiscovery.scan(window: Duration(seconds: seconds));
  final byVersion = <String, int>{};
  for (final d in found.values.toList()..sort((a, b) => a.ip.compareTo(b.ip))) {
    stdout.writeln('  $d');
    final v = d.version?.label ?? '?';
    byVersion[v] = (byVersion[v] ?? 0) + 1;
  }
  stdout.writeln('${found.length} dispositivos · versões: $byVersion');
  exit(0);
}
