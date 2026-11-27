import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../models/models.dart';
import '../state/home_controller.dart';

/// Full-screen clock shown when nobody is using the panel.
///
/// Pure black (the Tab S2 has an AMOLED screen, black pixels are off) and
/// the clock moves a little every minute so nothing stays burnt in. The
/// first touch only wakes the panel; it never reaches the controls below.
class ScreenSaver extends StatefulWidget {
  const ScreenSaver({
    super.key,
    required this.controller,
    required this.onWake,
  });

  final HomeController controller;
  final VoidCallback onWake;

  @override
  State<ScreenSaver> createState() => _ScreenSaverState();
}

class _ScreenSaverState extends State<ScreenSaver> {
  late DateTime _now = DateTime.now();
  Timer? _timer;
  final _random = Random();
  Alignment _spot = Alignment.center;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now();
    setState(() {
      if (now.minute != _now.minute) {
        _spot = Alignment(
          (_random.nextDouble() * 2 - 1) * 0.6,
          (_random.nextDouble() * 2 - 1) * 0.5,
        );
      }
      _now = now;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _weekdays = [
    'segunda',
    'terça',
    'quarta',
    'quinta',
    'sexta',
    'sábado',
    'domingo',
  ];
  static const _months = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  @override
  Widget build(BuildContext context) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    final date =
        '${_weekdays[_now.weekday - 1]}, ${_now.day} de ${_months[_now.month - 1]}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => widget.onWake(),
      onPanDown: (_) => widget.onWake(),
      // Material gives the texts the app's typography (the screensaver sits
      // above the navigator, outside any page).
      child: Material(
        color: Colors.black,
        child: AnimatedAlign(
          duration: const Duration(seconds: 4),
          curve: Curves.easeInOut,
          alignment: _spot,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$hh:$mm',
                style: const TextStyle(
                  fontSize: 168,
                  fontWeight: FontWeight.w200,
                  letterSpacing: -6,
                  height: 1,
                  color: Color(0xFFD9DCE1),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                date,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w300,
                  color: Color(0xFF7C8390),
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) => _Status(widget.controller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One quiet line: what is on in the house.
class _Status extends StatelessWidget {
  const _Status(this.c);

  final HomeController c;

  @override
  Widget build(BuildContext context) {
    final lights = c.lightsOn;
    final loads = c.activeLoads;
    final parts = <(IconData, Color, String)>[
      if (lights > 0)
        (
          Icons.lightbulb_rounded,
          AppColors.light,
          lights == 1 ? '1 luz acesa' : '$lights luzes acesas',
        ),
      for (final l in loads.take(2))
        (
          l.kind == DeviceKind.pump
              ? Icons.water_drop_rounded
              : Icons.power_rounded,
          AppColors.forKind(l.kind),
          l.name,
        ),
    ];
    if (parts.isEmpty) {
      return const Text(
        'Tudo apagado',
        style: TextStyle(fontSize: 18, color: Color(0xFF5B616C)),
      );
    }
    return Wrap(
      spacing: 28,
      children: [
        for (final (icon, color, label) in parts)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color.withValues(alpha: 0.7)),
              const SizedBox(width: AppSpace.sm),
              Text(
                label,
                style: const TextStyle(fontSize: 18, color: Color(0xFF8A919C)),
              ),
            ],
          ),
      ],
    );
  }
}
