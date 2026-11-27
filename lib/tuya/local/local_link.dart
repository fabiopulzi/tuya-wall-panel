/// Platform-neutral contracts for LAN control (no `dart:io` here, so the
/// web preview still compiles).
library;

import 'tuya_protocol.dart';

enum LinkState { disconnected, connecting, connected }

/// A live connection to one device.
abstract interface class LocalLink {
  String get deviceId;
  bool get isConnected;

  /// Latest value of every data point seen on this link.
  Map<String, Object?> get dps;

  /// Data points that changed, as reported by the device.
  Stream<Map<String, Object?>> get updates;
  Stream<LinkState> get states;

  Future<void> connect();
  Future<void> set(Map<String, Object?> values);
  void updateIp(String ip);
  Future<void> dispose();
}

/// A device announcing itself on the LAN.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.ip,
    required this.version,
  });

  final String id;
  final String ip;
  final TuyaVersion? version;

  @override
  String toString() => '$id @ $ip (v${version?.label ?? '?'})';
}

abstract interface class DeviceLocator {
  Stream<DiscoveredDevice> get devices;
  Future<void> start();
  Future<void> stop();
}

typedef LinkFactory = LocalLink Function({
  required String deviceId,
  required String localKey,
  required String ip,
  required TuyaVersion version,
});

/// Everything the hybrid repository needs for LAN control on this platform.
class LocalTransport {
  const LocalTransport({required this.locator, required this.linkFactory});
  final DeviceLocator locator;
  final LinkFactory linkFactory;
}
