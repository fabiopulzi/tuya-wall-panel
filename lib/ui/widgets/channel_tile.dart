import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../models/models.dart';
import '../room_icons.dart';

/// A big, tappable tile for one light / socket / pump inside a room.
class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.pending,
    required this.onTap,
  });

  final Channel channel;
  final bool pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = channel.isOn;
    final accent = AppColors.forKind(channel.kind);
    const duration = Duration(milliseconds: 260);

    final stateLabel = !channel.online
        ? 'Offline'
        : switch ((channel.kind, on)) {
            (DeviceKind.light, true) => 'Acesa',
            (DeviceKind.light, false) => 'Apagada',
            (_, true) => 'Ligado',
            (_, false) => 'Desligado',
          };

    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: on ? accent.withValues(alpha: 0.14) : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(
          color: on ? accent.withValues(alpha: 0.45) : AppColors.border,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.tile),
          onTap: channel.online ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: duration,
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: on ? accent : AppColors.surfaceHigh,
                        boxShadow: on
                            ? [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.5),
                                  blurRadius: 20,
                                ),
                              ]
                            : const [],
                      ),
                      child: Icon(
                        iconForChannel(channel),
                        size: 22,
                        color: on
                            ? const Color(0xFF14110A)
                            : AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    _MiniSwitch(on: on, color: accent, duration: duration),
                  ],
                ),
                const Spacer(),
                Text(
                  channel.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 18,
                  child: pending
                      ? const Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : Text(
                          stateLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: !channel.online
                                ? AppColors.danger
                                : on
                                ? accent
                                : AppColors.textTertiary,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniSwitch extends StatelessWidget {
  const _MiniSwitch({
    required this.on,
    required this.color,
    required this.duration,
  });

  final bool on;
  final Color color;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      width: 40,
      height: 24,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: on ? color : AppColors.surfaceHigh,
      ),
      child: AnimatedAlign(
        duration: duration,
        curve: Curves.easeOutBack,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? const Color(0xFF14110A) : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
