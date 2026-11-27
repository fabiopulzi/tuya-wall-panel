import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app/theme.dart';
import 'data/demo_repository.dart';
import 'data/home_repository.dart';
import 'data/hybrid_repository.dart';
import 'data/prefs_snapshot_cache.dart';
import 'data/tuya_cloud_repository.dart';
import 'state/home_controller.dart';
import 'tuya/local/platform_local.dart';
import 'tuya/tuya_cloud_client.dart';
import 'ui/dashboard_page.dart';

// Credentials come from --dart-define until the settings screen exists:
//   flutter run --dart-define=TUYA_ACCESS_ID=... --dart-define=TUYA_ACCESS_SECRET=...
const _accessId = String.fromEnvironment('TUYA_ACCESS_ID');
const _accessSecret = String.fromEnvironment('TUYA_ACCESS_SECRET');
const _region = String.fromEnvironment('TUYA_REGION', defaultValue: 'us');
const _home = String.fromEnvironment('TUYA_HOME');
// Dev only: point the web preview at tool/dev_proxy.py (Tuya has no CORS).
const _baseUrl = String.fromEnvironment('TUYA_BASE_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    // Wall panel: landscape, full screen, screen always on.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await WakelockPlus.enable();
  }

  final HomeRepository repository = _accessId.isEmpty
      ? DemoRepository()
      : HybridRepository(
          cloud: TuyaCloudRepository(
            TuyaCloudClient(
              accessId: _accessId,
              accessSecret: _accessSecret,
              baseUrl: _baseUrl.isNotEmpty
                  ? _baseUrl
                  : 'https://openapi.tuya$_region.com',
            ),
            homeName: _home.isEmpty ? null : _home,
          ),
          cache: PrefsSnapshotCache(),
          // LAN control on Android; null in the web preview (no sockets).
          transport: createLocalTransport(),
        );

  final controller = HomeController(repository)..load();
  runApp(WallPanelApp(controller: controller));
}

class WallPanelApp extends StatelessWidget {
  const WallPanelApp({super.key, required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tuya Wall Panel',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: DashboardPage(controller: controller),
    );
  }
}
