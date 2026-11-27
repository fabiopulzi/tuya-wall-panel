import 'local_link.dart';
import 'tuya_device_connection.dart';
import 'tuya_discovery.dart';

LocalTransport? createLocalTransport() => LocalTransport(
  locator: TuyaDiscovery(),
  linkFactory:
      ({required deviceId, required localKey, required ip, required version}) =>
          TuyaDeviceConnection(
            deviceId: deviceId,
            localKey: localKey,
            ip: ip,
            version: version,
          ),
);
