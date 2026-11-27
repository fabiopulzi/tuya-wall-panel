import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../models/models.dart';
import '../room_icons.dart';

class SceneBar extends StatelessWidget {
  const SceneBar({super.key, required this.scenes, required this.onRun});

  final List<Scene> scenes;
  final ValueChanged<Scene> onRun;

  @override
  Widget build(BuildContext context) {
    if (scenes.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: scenes.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
        itemBuilder: (context, i) =>
            _SceneButton(scene: scenes[i], onTap: () => onRun(scenes[i])),
      ),
    );
  }
}

class _SceneButton extends StatefulWidget {
  const _SceneButton({required this.scene, required this.onTap});

  final Scene scene;
  final VoidCallback onTap;

  @override
  State<_SceneButton> createState() => _SceneButtonState();
}

class _SceneButtonState extends State<_SceneButton> {
  bool _flash = false;

  Future<void> _run() async {
    widget.onTap();
    setState(() => _flash = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _flash = false);
  }

  @override
  Widget build(BuildContext context) {
    final color = _flash ? AppColors.light : AppColors.textPrimary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: _flash
            ? AppColors.light.withValues(alpha: 0.14)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _flash
              ? AppColors.light.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _run,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl - 4),
            child: Row(
              children: [
                Icon(iconForScene(widget.scene.icon), size: 22, color: color),
                const SizedBox(width: AppSpace.md - 2),
                Text(
                  widget.scene.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color,
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
