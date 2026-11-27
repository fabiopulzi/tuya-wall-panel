import 'dart:convert';

/// How the tablet behaves as a wall panel.
class PanelSettings {
  const PanelSettings({
    this.idleMinutes = 2,
    this.saverBrightness = 0.12,
    this.nightDim = true,
  });

  /// Minutes without a touch before the screensaver; 0 never.
  final int idleMinutes;

  /// Screen brightness while the screensaver shows, 0..1.
  final double saverBrightness;

  /// Darker screensaver at night (22h to 6h).
  final bool nightDim;

  static const idleChoices = [1, 2, 5, 10, 0];
  static const nightStart = 22;
  static const nightEnd = 6;

  static bool isNight(DateTime t) => t.hour >= nightStart || t.hour < nightEnd;

  /// Brightness for the screensaver at [now].
  double saverBrightnessAt(DateTime now) => nightDim && isNight(now)
      ? (saverBrightness * 0.3).clamp(0.01, 1.0)
      : saverBrightness;

  PanelSettings copyWith({
    int? idleMinutes,
    double? saverBrightness,
    bool? nightDim,
  }) => PanelSettings(
    idleMinutes: idleMinutes ?? this.idleMinutes,
    saverBrightness: saverBrightness ?? this.saverBrightness,
    nightDim: nightDim ?? this.nightDim,
  );

  String encode() => jsonEncode({
    'idleMinutes': idleMinutes,
    'saverBrightness': saverBrightness,
    'nightDim': nightDim,
  });

  static PanelSettings decode(String raw) {
    final j = (jsonDecode(raw) as Map).cast<String, Object?>();
    const d = PanelSettings();
    return PanelSettings(
      idleMinutes: (j['idleMinutes'] as num?)?.toInt() ?? d.idleMinutes,
      saverBrightness:
          (j['saverBrightness'] as num?)?.toDouble() ?? d.saverBrightness,
      nightDim: j['nightDim'] as bool? ?? d.nightDim,
    );
  }
}

abstract interface class PanelSettingsStore {
  Future<PanelSettings?> read();
  Future<void> write(PanelSettings settings);
}

class MemoryPanelSettingsStore implements PanelSettingsStore {
  MemoryPanelSettingsStore([this.value]);
  PanelSettings? value;

  @override
  Future<PanelSettings?> read() async => value;

  @override
  Future<void> write(PanelSettings settings) async => value = settings;
}
