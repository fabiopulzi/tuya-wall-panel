import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android features the panel needs (see MainActivity.kt). Every call is a
/// no-op where the platform does not have them (web preview, tests).
abstract interface class SystemBridge {
  /// 0..1, or null to follow Android (including adaptive brightness).
  Future<void> setBrightness(double? value);

  /// Whether the panel is the tablet's home screen (opens on boot).
  Future<bool> isDefaultHome();

  Future<void> openHomeSettings();
  Future<void> openDisplaySettings();
  Future<void> openSettings();
}

class AndroidSystemBridge implements SystemBridge {
  static const _channel = MethodChannel('painel/system');

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> setBrightness(double? value) =>
      _call<void>('setBrightness', {'value': value});

  @override
  Future<bool> isDefaultHome() async =>
      await _call<bool>('isDefaultHome') ?? false;

  @override
  Future<void> openHomeSettings() => _call<bool>('openHomeSettings');

  @override
  Future<void> openDisplaySettings() => _call<bool>('openDisplaySettings');

  @override
  Future<void> openSettings() => _call<bool>('openSettings');
}

/// Does nothing; records the last brightness (tests).
class FakeSystemBridge implements SystemBridge {
  double? brightness;
  int brightnessCalls = 0;
  bool home = false;

  @override
  Future<void> setBrightness(double? value) async {
    brightness = value;
    brightnessCalls++;
  }

  @override
  Future<bool> isDefaultHome() async => home;

  @override
  Future<void> openHomeSettings() async {}

  @override
  Future<void> openDisplaySettings() async {}

  @override
  Future<void> openSettings() async {}
}
