import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../room_icons.dart';

/// Returned by [showNameDialog] when the person chose "Ocultar do painel".
const hideRequest = '\u0000hide';

/// Asks for a name. Returns null on cancel, `''` for "use the original",
/// or [hideRequest] when [offerHide] is set and the key should be hidden.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String initial,
  String? original,
  bool offerHide = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(
    title: title,
    initial: initial,
    original: original,
    offerHide: offerHide,
  ),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.original,
    required this.offerHide,
  });

  final String title;
  final String initial;
  final String? original;
  final bool offerHide;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _pop([String? value]) => Navigator.of(context).pop(value);

  @override
  Widget build(BuildContext context) {
    final original = widget.original;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (v) => _pop(v.trim()),
            ),
            if (original != null) ...[
              const SizedBox(height: AppSpace.md),
              Text(
                'No Smart Life: $original',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        if (widget.offerHide)
          TextButton.icon(
            onPressed: () => _pop(hideRequest),
            icon: const Icon(Icons.visibility_off_rounded, size: 18),
            label: const Text('Ocultar do painel'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
          ),
        if (original != null && widget.initial != original)
          TextButton(
            onPressed: () => _pop(''),
            child: const Text('Nome original'),
          ),
        TextButton(onPressed: _pop, child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => _pop(_text.text.trim()),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(title),
      content: SizedBox(width: 420, child: Text(message)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Picks one of [roomIcons]; returns its key.
Future<String?> showIconPicker(BuildContext context, {String? selected}) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: const Text('Ícone do cômodo'),
      content: SizedBox(
        width: 460,
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final MapEntry(:key, :value) in roomIcons.entries)
              Material(
                color: key == selected
                    ? AppColors.light.withValues(alpha: 0.2)
                    : AppColors.surfaceRaised,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: key == selected ? AppColors.light : AppColors.border,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.of(context).pop(key),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Icon(value, size: 30, color: AppColors.textPrimary),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
