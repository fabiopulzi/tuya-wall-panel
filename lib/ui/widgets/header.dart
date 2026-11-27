import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../models/models.dart';
import '../../state/home_controller.dart';
import '../settings/layout_editor_page.dart';

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key, required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(child: _Clock()),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _Status(controller: controller),
        ),
      ],
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Tick on the minute boundary, then every minute.
    final untilNextMinute = Duration(seconds: 60 - _now.second);
    _timer = Timer(untilNextMinute, () {
      _tick();
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    });
  }

  void _tick() => setState(() => _now = DateTime.now());

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _weekdays = [
    'Segunda',
    'Terça',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sábado',
    'Domingo',
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

  String get _greeting => switch (_now.hour) {
    < 5 => 'Boa noite',
    < 12 => 'Bom dia',
    < 18 => 'Boa tarde',
    _ => 'Boa noite',
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$hh:$mm', style: text.displayLarge),
        const SizedBox(height: AppSpace.sm),
        Text(
          '$_greeting  ·  ${_weekdays[_now.weekday - 1]}, '
          '${_now.day} de ${_months[_now.month - 1]}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodyMedium?.copyWith(fontSize: 16),
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    final lights = controller.lightsOn;
    final loads = controller.activeLoads;

    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Chip(
          icon: Icons.lightbulb_rounded,
          color: lights > 0 ? AppColors.light : AppColors.textTertiary,
          label: switch (lights) {
            0 => 'Luzes apagadas',
            1 => '1 luz acesa',
            _ => '$lights luzes acesas',
          },
        ),
        for (final c in loads.take(1))
          _Chip(
            icon: c.kind == DeviceKind.pump
                ? Icons.water_drop_rounded
                : Icons.power_rounded,
            color: AppColors.forKind(c.kind),
            label: c.name,
          ),
        if (loads.length > 1)
          _Chip(
            icon: Icons.add_rounded,
            color: AppColors.textSecondary,
            label: '${loads.length - 1}',
          ),
        if (controller.lanStatus case (:final local, :final total)
            when total > 0)
          _Chip(
            icon: local > 0 ? Icons.wifi_rounded : Icons.cloud_outlined,
            color: local == total
                ? AppColors.plug
                : local > 0
                ? AppColors.light
                : AppColors.textTertiary,
            label: local > 0 ? 'Rede local $local/$total' : 'Via nuvem',
          ),
        const SizedBox(width: AppSpace.xs),
        _AllOffButton(
          enabled: controller.allOffTargets.isNotEmpty,
          onPressed: controller.allLightsOff,
        ),
        _SettingsButton(
          onPressed: () => LayoutEditorPage.open(context, controller),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpace.sm),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllOffButton extends StatelessWidget {
  const _AllOffButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: enabled ? onPressed : null,
          child: const SizedBox(
            height: 44,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.lg + 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.power_settings_new_rounded,
                    size: 18,
                    color: AppColors.textPrimary,
                  ),
                  SizedBox(width: AppSpace.sm),
                  Text(
                    'Apagar tudo',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onPressed,
      child: const SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          Icons.tune_rounded,
          size: 20,
          color: AppColors.textSecondary,
        ),
      ),
    ),
  );
}
