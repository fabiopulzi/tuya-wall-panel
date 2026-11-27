import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuya_wall_panel/models/panel_settings.dart';
import 'package:tuya_wall_panel/platform/system_bridge.dart';
import 'package:tuya_wall_panel/state/panel_mode.dart';

void main() {
  late FakeSystemBridge bridge;
  late MemoryPanelSettingsStore store;
  var now = DateTime(2026, 11, 27, 15);

  PanelMode build() =>
      PanelMode(bridge: bridge, store: store, clock: () => now);

  setUp(() {
    bridge = FakeSystemBridge();
    store = MemoryPanelSettingsStore();
    now = DateTime(2026, 11, 27, 15);
  });

  test('the screensaver comes up after the idle time and dims', () {
    fakeAsync((async) {
      final mode = build()..load();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1, seconds: 59));
      expect(mode.saverOn, isFalse);
      async.elapse(const Duration(seconds: 2));
      expect(mode.saverOn, isTrue);
      expect(bridge.brightness, const PanelSettings().saverBrightness);
    });
  });

  test('touches postpone it; waking gives brightness back to Android', () {
    fakeAsync((async) {
      final mode = build()..load();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1, seconds: 30));
      mode.userActivity();
      async.elapse(const Duration(minutes: 1, seconds: 30));
      expect(mode.saverOn, isFalse);

      async.elapse(const Duration(minutes: 1));
      expect(mode.saverOn, isTrue);
      mode.wake();
      async.flushMicrotasks();
      expect(mode.saverOn, isFalse);
      expect(bridge.brightness, isNull, reason: 'null = follow Android');
    });
  });

  test('"Nunca" disables it', () {
    fakeAsync((async) {
      final mode = build()..load();
      async.flushMicrotasks();
      mode.update(const PanelSettings(idleMinutes: 0));
      async.elapse(const Duration(hours: 3));
      expect(mode.saverOn, isFalse);
    });
  });

  test('darker at night', () {
    const s = PanelSettings(saverBrightness: 0.2);
    expect(s.saverBrightnessAt(DateTime(2026, 1, 1, 15)), 0.2);
    expect(s.saverBrightnessAt(DateTime(2026, 1, 1, 23)), closeTo(0.06, 1e-9));
    expect(s.saverBrightnessAt(DateTime(2026, 1, 1, 5)), closeTo(0.06, 1e-9));
    expect(
      s.copyWith(nightDim: false).saverBrightnessAt(DateTime(2026, 1, 1, 23)),
      0.2,
    );
  });

  test('settings are saved and read back', () async {
    final mode = build();
    await mode.load();
    await mode.update(
      const PanelSettings(
        idleMinutes: 5,
        saverBrightness: 0.3,
        nightDim: false,
      ),
    );
    final back = PanelSettings.decode(store.value!.encode());
    expect(
      (back.idleMinutes, back.saverBrightness, back.nightDim),
      (5, 0.3, false),
    );
    mode.dispose();
  });
}
