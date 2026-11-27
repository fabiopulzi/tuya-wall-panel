import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../models/models.dart';
import '../state/home_controller.dart';
import 'room_icons.dart';
import 'settings/dialogs.dart';
import 'settings/layout_editor_page.dart';
import 'widgets/channel_tile.dart';

Future<void> showRoomSheet(
  BuildContext context, {
  required HomeController controller,
  required Room room,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, _, _) =>
        _RoomSheet(controller: controller, room: room),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 14 * animation.value,
          sigmaY: 14 * animation.value,
        ),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

class _RoomSheet extends StatelessWidget {
  const _RoomSheet({required this.controller, required this.room});

  final HomeController controller;
  final Room room;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final text = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (size.width * 0.88).clamp(320, 920),
          maxHeight: size.height * 0.84,
        ),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(32),
          clipBehavior: Clip.antiAlias,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final channels = controller.channelsIn(room.id);
              final lights = channels
                  .where((c) => c.kind == DeviceKind.light)
                  .toList();
              final lightsOn = lights.where((c) => c.isOn).length;

              return Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            iconForRoom(room),
                            size: 30,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: AppSpace.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(room.name, style: text.headlineMedium),
                              Text(
                                lights.isEmpty
                                    ? '${channels.length} dispositivos'
                                    : '$lightsOn de ${lights.length} luzes acesas',
                                style: text.bodyMedium?.copyWith(fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                        if (lights.length > 1) ...[
                          _PillButton(
                            label: 'Apagar',
                            icon: Icons.dark_mode_rounded,
                            enabled: lightsOn > 0,
                            onTap: () =>
                                controller.setRoomLights(room.id, false),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          _PillButton(
                            label: 'Acender',
                            icon: Icons.light_mode_rounded,
                            enabled: lightsOn < lights.length,
                            highlight: true,
                            onTap: () =>
                                controller.setRoomLights(room.id, true),
                          ),
                          const SizedBox(width: AppSpace.md),
                        ],
                        IconButton(
                          tooltip: 'Personalizar este cômodo',
                          onPressed: () {
                            Navigator.of(context).pop();
                            LayoutEditorPage.open(
                              context,
                              controller,
                              roomId: room.id,
                            );
                          },
                          iconSize: 24,
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.surfaceHigh,
                            fixedSize: const Size(52, 52),
                          ),
                          icon: const Icon(
                            Icons.tune_rounded,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          iconSize: 28,
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.surfaceHigh,
                            fixedSize: const Size(52, 52),
                          ),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xl),
                    Flexible(
                      child: GridView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(right: 8),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 230,
                              mainAxisExtent: 156,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                            ),
                        itemCount: channels.length,
                        itemBuilder: (context, i) {
                          final c = channels[i];
                          return ChannelTile(
                            channel: c,
                            pending: controller.isPending(c.id),
                            onTap: () => controller.toggle(c),
                            onLongPress: () => _renameOrHide(context, c),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _renameOrHide(BuildContext context, Channel c) async {
    final original = controller.channel(c.id)?.name;
    final result = await showNameDialog(
      context,
      title: 'Tecla',
      initial: c.name,
      original: original,
      offerHide: true,
    );
    switch (result) {
      case null:
        return;
      case hideRequest:
        await controller.hideChannel(c.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '"${c.name}" saiu do painel. Para trazer de volta, use '
                'Personalizar → Ocultas.',
              ),
            ),
          );
        }
      case final name:
        await controller.renameChannel(c.id, name == original ? null : name);
    }
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.highlight = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = highlight ? const Color(0xFF2B1A00) : AppColors.textPrimary;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: highlight ? AppColors.light : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: AppSpace.sm),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: fg,
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
