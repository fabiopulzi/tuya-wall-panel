import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/panel_settings.dart';
import '../platform/system_bridge.dart';

/// Wall-panel behaviour: after a while without a touch the screensaver
/// comes up and the screen dims; a touch brings the panel back at the
/// brightness Android chooses (adaptive, if enabled there).
class PanelMode extends ChangeNotifier {
  PanelMode({
    required this.bridge,
    PanelSettingsStore? store,
    DateTime Function()? clock,
  }) : _store = store ?? MemoryPanelSettingsStore(),
       _clock = clock ?? DateTime.now;

  final SystemBridge bridge;
  final PanelSettingsStore _store;
  final DateTime Function() _clock;

  PanelSettings settings = const PanelSettings();
  bool saverOn = false;

  /// Whether the panel is the tablet's home screen (refreshed on demand).
  bool isHome = false;

  Timer? _idle;
  Timer? _night;

  Future<void> load() async {
    settings = await _store.read() ?? const PanelSettings();
    isHome = await bridge.isDefaultHome();
    _restartIdle();
    notifyListeners();
  }

  Future<void> update(PanelSettings next) async {
    settings = next;
    _restartIdle();
    if (saverOn) await _applySaverBrightness();
    notifyListeners();
    await _store.write(next);
  }

  Future<void> refreshHome() async {
    final home = await bridge.isDefaultHome();
    if (home != isHome) {
      isHome = home;
      notifyListeners();
    }
  }

  /// Any touch on the panel.
  void userActivity() {
    if (!saverOn) _restartIdle();
  }

  Future<void> showSaver() async {
    _idle?.cancel();
    if (saverOn) return;
    saverOn = true;
    notifyListeners();
    await _applySaverBrightness();
    // Re-check every 10 min so the night dimming kicks in on its own.
    _night?.cancel();
    _night = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _applySaverBrightness(),
    );
  }

  Future<void> wake() async {
    _night?.cancel();
    if (saverOn) {
      saverOn = false;
      notifyListeners();
    }
    _restartIdle();
    await bridge.setBrightness(null);
  }

  Future<void> _applySaverBrightness() =>
      bridge.setBrightness(settings.saverBrightnessAt(_clock()));

  void _restartIdle() {
    _idle?.cancel();
    final minutes = settings.idleMinutes;
    if (minutes <= 0) return;
    _idle = Timer(Duration(minutes: minutes), showSaver);
  }

  @override
  void dispose() {
    _idle?.cancel();
    _night?.cancel();
    super.dispose();
  }
}

/// Makes [PanelMode] reachable from any route (settings screen).
class PanelModeScope extends InheritedNotifier<PanelMode> {
  const PanelModeScope({
    super.key,
    required PanelMode mode,
    required super.child,
  }) : super(notifier: mode);

  static PanelMode? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelModeScope>()?.notifier;
}
