import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'local_link.dart';
import 'tuya_protocol.dart';

export 'local_link.dart' show DiscoveredDevice;

/// Listens for the UDP broadcasts Tuya devices send every few seconds:
///   6666  plain JSON (3.1)
///   6667  AES-ECB with a well-known key (3.3 / 3.4)
///   7000  AES-GCM 6699 frames (3.5)
class TuyaDiscovery implements DeviceLocator {
  final _controller = StreamController<DiscoveredDevice>.broadcast();
  final List<RawDatagramSocket> _sockets = [];
  final Map<String, DiscoveredDevice> found = {};

  @override
  Stream<DiscoveredDevice> get devices => _controller.stream;

  @override
  Future<void> start() async {
    for (final port in const [6666, 6667, 7000]) {
      try {
        final s = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          port,
          reuseAddress: true,
          reusePort: !Platform.isWindows && !Platform.isAndroid,
        );
        s.broadcastEnabled = true;
        s.listen((event) {
          if (event != RawSocketEvent.read) return;
          final dg = s.receive();
          if (dg != null) _handle(dg);
        });
        _sockets.add(s);
      } on SocketException {
        // Port busy (another Tuya app on this machine): skip it.
      }
    }
    // 3.5 devices answer faster when asked.
    unawaited(_requestInfo());
  }

  Future<void> _requestInfo() async {
    final s = _sockets.where((s) => s.port == 7000).firstOrNull;
    if (s == null) return;
    final body = Uint8List.fromList(utf8.encode(jsonEncode({'from': 'app'})));
    final frame = pack6699(seq: 0, cmd: 0x25, payload: body, key: udpKey);
    try {
      s.send(frame, InternetAddress('255.255.255.255'), 7000);
    } on SocketException {
      // Broadcast not permitted on this network; passive listening still works.
    }
  }

  void _handle(Datagram dg) {
    final json = decodeBroadcast(dg.data);
    if (json == null) return;
    final id = (json['gwId'] ?? json['devId']) as String?;
    if (id == null) return;
    final device = DiscoveredDevice(
      id: id,
      ip: (json['ip'] as String?) ?? dg.address.address,
      version: TuyaVersion.parse(json['version']),
    );
    final previous = found[id];
    found[id] = device;
    if (previous?.ip != device.ip || previous?.version != device.version) {
      _controller.add(device);
    }
  }

  /// Decodes one broadcast datagram, or returns null if it is not Tuya.
  static Map<String, Object?>? decodeBroadcast(Uint8List data) {
    try {
      Uint8List payload;
      final r = unpackFrame(data, key: udpKey, hasRetcode: null);
      if (r is Complete) {
        payload = r.frame.payload;
        final isJson = payload.isNotEmpty && payload.first == 0x7B;
        // 55AA broadcasts: plain JSON on 6666, ECB-encrypted on 6667. 6699
        // frames arrive already decrypted.
        if (!isJson && data[2] == 0x55) {
          // The retcode heuristic does not apply to 55AA; retry without it.
          final noRet = unpackFrame(data, hasRetcode: false) as Complete;
          payload = noRet.frame.payload;
          if (payload.first != 0x7B) {
            payload = _tryEcb(r.frame.payload) ?? _tryEcb(payload)!;
          }
        }
      } else {
        payload = aesEcbDecrypt(udpKey, data);
      }
      final text = utf8.decode(payload, allowMalformed: true);
      final json = jsonDecode(text.replaceAll('\u0000', '').trim());
      return json is Map<String, Object?> ? json : null;
    } on Object {
      return null;
    }
  }

  static Uint8List? _tryEcb(Uint8List p) {
    try {
      return aesEcbDecrypt(udpKey, p);
    } on Object {
      return null;
    }
  }

  /// Collects announcements for [window], then stops.
  static Future<Map<String, DiscoveredDevice>> scan({
    Duration window = const Duration(seconds: 12),
  }) async {
    final d = TuyaDiscovery();
    await d.start();
    await Future<void>.delayed(window);
    await d.stop();
    return d.found;
  }

  @override
  Future<void> stop() async {
    for (final s in _sockets) {
      s.close();
    }
    _sockets.clear();
    await _controller.close();
  }
}
