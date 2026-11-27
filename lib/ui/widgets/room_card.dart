import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../models/models.dart';
import '../room_icons.dart';

/// One room on the dashboard.
///
/// Off: a quiet dark tile. On: the card picks up a soft glow in the color of
/// what is running (warm for lights, aqua for the pool pump, green for
/// sockets), so the state of the whole house reads at a glance.
class RoomCard extends StatelessWidget {
  const RoomCard({
    super.key,
    required this.room,
    required this.channels,
    required this.onOpen,
    required this.onToggleLights,
  });

  final Room room;
  final List<Channel> channels;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggleLights;

  @override
  Widget build(BuildContext context) {
    final lights = channels.where((c) => c.kind == DeviceKind.light).toList();
    final lightsOn = lights.where((c) => c.isOn && c.online).length;
    final loadsOn = channels
        .where((c) => c.kind != DeviceKind.light && c.isOn && c.online)
        .toList();
    final active = lightsOn > 0 || loadsOn.isNotEmpty;
    final accent = lightsOn > 0
        ? AppColors.light
        : loadsOn.isNotEmpty
        ? AppColors.forKind(loadsOn.first.kind)
        : AppColors.textSecondary;

    final text = Theme.of(context).textTheme;
    const duration = Duration(milliseconds: 320);

    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: active ? AppColors.surfaceRaised : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: active ? accent.withValues(alpha: 0.32) : AppColors.border,
        ),
        gradient: active
            ? RadialGradient(
                center: const Alignment(-0.9, -1.0),
                radius: 1.35,
                colors: [
                  accent.withValues(alpha: 0.30),
                  accent.withValues(alpha: 0.07),
                  AppColors.surfaceRaised.withValues(alpha: 0),
                ],
                stops: const [0, 0.55, 1],
              )
            : null,
        boxShadow: active
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.12),
                  blurRadius: 32,
                  spreadRadius: -4,
                  offset: const Offset(0, 10),
                ),
              ]
            : const [],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RoomBadge(
                      icon: iconForRoom(room),
                      color: accent,
                      active: active,
                      duration: duration,
                    ),
                    const Spacer(),
                    if (lights.isNotEmpty)
                      _PowerButton(
                        on: lightsOn > 0,
                        duration: duration,
                        onTap: () => onToggleLights(lightsOn == 0),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  room.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge,
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  _summary(lights.length, lightsOn, loadsOn),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: active
                        ? AppColors.textPrimary.withValues(alpha: 0.72)
                        : null,
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                SizedBox(
                  height: 22,
                  child: Row(
                    children: [
                      Expanded(
                        child: _ChannelDots(
                          channels: channels,
                          duration: duration,
                        ),
                      ),
                      if (loadsOn.isNotEmpty) _LoadTag(loads: loadsOn),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _summary(int lights, int lightsOn, List<Channel> loadsOn) {
    if (lights > 0) {
      return switch (lightsOn) {
        0 => lights == 1 ? 'Luz apagada' : 'Luzes apagadas',
        _ when lightsOn == lights => lights == 1 ? 'Luz acesa' : 'Todas acesas',
        _ => '$lightsOn de $lights acesas',
      };
    }
    return loadsOn.isEmpty ? 'Tudo desligado' : 'Ligado';
  }
}

/// Small tag for non-light loads that are running (pool pump, sockets).
class _LoadTag extends StatelessWidget {
  const _LoadTag({required this.loads});

  final List<Channel> loads;

  @override
  Widget build(BuildContext context) {
    final first = loads.first;
    final color = AppColors.forKind(first.kind);
    final label = loads.length > 1
        ? '${loads.length} ligados'
        : first.kind == DeviceKind.pump
        ? 'Filtro'
        : first.name;
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            first.kind == DeviceKind.pump
                ? Icons.water_drop_rounded
                : Icons.power_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomBadge extends StatelessWidget {
  const _RoomBadge({
    required this.icon,
    required this.color,
    required this.active,
    required this.duration,
  });

  final IconData icon;
  final Color color;
  final bool active;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.18) : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        icon,
        size: 26,
        color: active ? color : AppColors.textSecondary,
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.on,
    required this.duration,
    required this.onTap,
  });

  final bool on;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 56px hit area around a 44px visual for easy taps on a wall.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AnimatedContainer(
          duration: duration,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? AppColors.light : AppColors.surfaceHigh,
            boxShadow: on
                ? [
                    BoxShadow(
                      color: AppColors.light.withValues(alpha: 0.45),
                      blurRadius: 18,
                    ),
                  ]
                : const [],
          ),
          child: Icon(
            Icons.power_settings_new_rounded,
            size: 22,
            color: on ? const Color(0xFF2B1A00) : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// A dot per output: a tiny floor plan of what is on in the room.
class _ChannelDots extends StatelessWidget {
  const _ChannelDots({required this.channels, required this.duration});

  final List<Channel> channels;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in channels)
              AnimatedContainer(
                duration: duration,
                width: c.kind == DeviceKind.light ? 8 : 16,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: !c.online
                      ? AppColors.danger.withValues(alpha: 0.6)
                      : c.isOn
                      ? AppColors.forKind(c.kind)
                      : AppColors.surfaceHigh,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
