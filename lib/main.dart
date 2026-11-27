import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app/theme.dart';
import 'data/demo_repository.dart';
import 'data/home_repository.dart';
import 'data/hybrid_repository.dart';
import 'data/prefs_layout_store.dart';
import 'data/prefs_panel_settings_store.dart';
import 'data/prefs_snapshot_cache.dart';
import 'data/tuya_cloud_repository.dart';
import 'platform/system_bridge.dart';
import 'state/home_controller.dart';
import 'state/panel_mode.dart';
import 'tuya/local/platform_local.dart';
import 'tuya/tuya_cloud_client.dart';
import 'ui/dashboard_page.dart';
import 'ui/screensaver.dart';

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

  // The layout set up on the tablet lives in its own store, so neither a
  // cloud sync nor a new app version overwrites it.
  final controller = HomeController(repository, layouts: PrefsLayoutStore())
    ..load();
  final mode = PanelMode(
    bridge: AndroidSystemBridge(),
    store: PrefsPanelSettingsStore(),
  )..load();
  runApp(WallPanelApp(controller: controller, mode: mode));
}

class WallPanelApp extends StatefulWidget {
  const WallPanelApp({super.key, required this.controller, required this.mode});

  final HomeController controller;
  final PanelMode mode;

  @override
  State<WallPanelApp> createState() => _WallPanelAppState();
}

class _WallPanelAppState extends State<WallPanelApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android settings: the home screen choice may have changed.
    if (state == AppLifecycleState.resumed) {
      widget.mode
        ..refreshHome()
        ..wake();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    return MaterialApp(
      title: 'Painel Casa',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: DashboardPage(controller: widget.controller),
      // Above every route and dialog: any touch counts as activity, and the
      // screensaver covers everything.
      builder: (context, child) => PanelModeScope(
        mode: mode,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => mode.userActivity(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ?child,
              ListenableBuilder(
                listenable: mode,
                builder: (context, _) => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  child: mode.saverOn
                      ? ScreenSaver(
                          controller: widget.controller,
                          onWake: mode.wake,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
