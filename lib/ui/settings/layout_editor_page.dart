import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../models/models.dart';
import '../../models/panel_layout.dart';
import '../../models/panel_settings.dart';
import '../../state/home_controller.dart';
import '../../state/panel_mode.dart';
import '../room_icons.dart';
import 'dialogs.dart';

/// "Personalizar painel": rooms on the left, the selected room's keys on the
/// right. Keys are dragged to reorder them, onto another room to move them,
/// or onto "Ocultas" to take them off the panel. Every change is saved on
/// the tablet at once.
class LayoutEditorPage extends StatefulWidget {
  const LayoutEditorPage({
    super.key,
    required this.controller,
    this.initialRoomId,
  });

  final HomeController controller;
  final String? initialRoomId;

  static Future<void> open(
    BuildContext context,
    HomeController controller, {
    String? roomId,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          LayoutEditorPage(controller: controller, initialRoomId: roomId),
    ),
  );

  @override
  State<LayoutEditorPage> createState() => _LayoutEditorPageState();
}

const _hiddenId = '\u0000hidden';
const _allOffId = '\u0000allOff';

class _LayoutEditorPageState extends State<LayoutEditorPage> {
  HomeController get c => widget.controller;
  late PanelLayout layout = c.editableLayout;
  late String selected =
      widget.initialRoomId ??
      (layout.rooms.isEmpty ? _hiddenId : layout.rooms.first.id);

  final _roomScroll = ScrollController();
  final _keyScroll = ScrollController();
  final _roomListKey = GlobalKey();
  final _keyListKey = GlobalKey();
  Timer? _scrollTimer;
  Offset? _dragPos;
  String? _dragging;

  /// 0: rooms and keys, 1: actions.
  int _tab = 0;

  /// Action open in the "Ações" tab.
  String _action = _allOffId;
  final _actionScroll = ScrollController();

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _roomScroll.dispose();
    _keyScroll.dispose();
    _actionScroll.dispose();
    super.dispose();
  }

  void _apply(PanelLayout next) {
    unawaited(c.updateLayout(next));
    setState(() {
      layout = c.editableLayout;
      if (selected != _hiddenId && layout.room(selected) == null) {
        selected = layout.rooms.isEmpty ? _hiddenId : layout.rooms.first.id;
      }
    });
  }

  // --- drag & auto-scroll ---------------------------------------------------

  void _dragStarted(String id) {
    setState(() => _dragging = id);
    _scrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _autoScroll(),
    );
  }

  void _dragMoved(DragUpdateDetails d) => _dragPos = d.globalPosition;

  void _dragEnded() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _dragPos = null;
    if (mounted) setState(() => _dragging = null);
  }

  /// Scrolls a list while a key is held near its top or bottom edge.
  void _autoScroll() {
    final pos = _dragPos;
    if (pos == null) return;
    for (final (key, scroll) in [
      (_keyListKey, _keyScroll),
      (_roomListKey, _roomScroll),
    ]) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !scroll.hasClients) continue;
      final p = box.globalToLocal(pos);
      if (p.dx < 0 || p.dx > box.size.width) continue;
      const edge = 80.0;
      double delta = 0;
      final bottom = box.size.height - p.dy;
      if (p.dy < 0 || bottom < 0) continue; // outside this list
      if (p.dy < edge) delta = -(edge - p.dy) / 5;
      if (bottom < edge) delta = (edge - bottom) / 5;
      if (delta == 0) continue;
      final max = scroll.position.maxScrollExtent;
      scroll.jumpTo((scroll.offset + delta).clamp(0, max));
    }
  }

  // --- actions ---------------------------------------------------------------

  void _moveTo(String channelId, String target, {int? index}) => _apply(
    target == _hiddenId
        ? layout.moveChannel(channelId)
        : layout.moveChannel(channelId, toRoom: target, index: index),
  );

  void _show(String channelId) {
    if (layout.rooms.isEmpty) return;
    final home = c.channel(channelId)?.roomId;
    final target = layout.room(home ?? '') != null
        ? home!
        : layout.rooms.first.id;
    _moveTo(channelId, target);
    _toast('Tecla de volta em "${layout.room(target)!.name}"');
  }

  Future<void> _renameKey(String channelId) async {
    final original = c.channel(channelId)?.name;
    final name = await showNameDialog(
      context,
      title: 'Nome da tecla',
      initial: c.nameOf(channelId),
      original: original,
    );
    if (name == null) return;
    _apply(layout.renameChannel(channelId, name == original ? null : name));
  }

  Future<void> _renameRoom(LayoutRoom room) async {
    final name = await showNameDialog(
      context,
      title: 'Nome do cômodo',
      initial: room.name,
    );
    if (name == null || name.isEmpty) return;
    _apply(layout.updateRoom(room.id, name: name));
  }

  Future<void> _pickIcon(LayoutRoom room) async {
    final icon = await showIconPicker(context, selected: room.icon);
    if (icon != null) _apply(layout.updateRoom(room.id, icon: icon));
  }

  Future<void> _addRoom() async {
    final name = await showNameDialog(
      context,
      title: 'Novo cômodo',
      initial: '',
    );
    if (name == null || name.isEmpty) return;
    final id = 'u${DateTime.now().millisecondsSinceEpoch}';
    _apply(layout.addRoom(LayoutRoom(id: id, name: name)));
    setState(() => selected = id);
    _toast('Abra outro cômodo e arraste teclas até "$name"');
  }

  Future<void> _deleteRoom(LayoutRoom room) async {
    final n = room.channelIds.length;
    final ok = await showConfirmDialog(
      context,
      title: 'Excluir "${room.name}"?',
      message: n == 0
          ? 'O cômodo está vazio.'
          : 'As $n teclas dele vão para "Ocultas", de onde podem ser '
                'arrastadas para outro cômodo.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (ok) _apply(layout.removeRoom(room.id));
  }

  Future<void> _reset() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Voltar ao Smart Life?',
      message:
          'Os cômodos, a ordem, os nomes e as teclas ocultas voltam a ser '
          'os do app Smart Life. A personalização feita aqui é apagada.',
      confirmLabel: 'Restaurar',
      destructive: true,
    );
    if (!ok) return;
    await c.resetLayout();
    setState(() {
      layout = c.editableLayout;
      selected = layout.rooms.isEmpty ? _hiddenId : layout.rooms.first.id;
    });
  }

  Future<void> _addAction() async {
    final name = await showNameDialog(context, title: 'Nova ação', initial: '');
    if (name == null || name.isEmpty) return;
    final id = 'a${DateTime.now().millisecondsSinceEpoch}';
    _apply(layout.addAction(PanelAction(id: id, name: name)));
    setState(() => _action = id);
    _toast('Toque nas teclas para escolher o que "$name" faz');
  }

  Future<void> _renameAction(PanelAction a) async {
    final name = await showNameDialog(
      context,
      title: 'Nome da ação',
      initial: a.name,
    );
    if (name == null || name.isEmpty) return;
    _apply(layout.updateAction(a.id, name: name));
  }

  Future<void> _pickActionIcon(PanelAction a) async {
    final icon = await showIconPicker(
      context,
      selected: a.icon,
      icons: actionIcons,
      title: 'Ícone da ação',
    );
    if (icon != null) _apply(layout.updateAction(a.id, icon: icon));
  }

  Future<void> _deleteAction(PanelAction a) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Excluir "${a.name}"?',
      message: 'A ação sai da tela principal. Nenhuma luz é acionada.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok) return;
    _apply(layout.removeAction(a.id));
    setState(() => _action = _allOffId);
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  customized: c.isCustomized,
                  tab: _tab,
                  onTab: (t) => setState(() => _tab = t),
                  onBack: () => Navigator.of(context).pop(),
                  onReset: _reset,
                ),
                const SizedBox(height: AppSpace.lg),
                Expanded(
                  child: _tab == 2
                      ? _buildPanelTab()
                      : _tab == 1
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 300, child: _buildActionList()),
                            const SizedBox(width: AppSpace.lg),
                            Expanded(child: _buildActionEditor()),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 300, child: _buildRooms()),
                            const SizedBox(width: AppSpace.lg),
                            Expanded(child: _buildKeys()),
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

  Widget _buildRooms() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 10, 4),
            child: Row(
              children: [
                const Expanded(child: _SectionLabel('CÔMODOS')),
                TextButton.icon(
                  onPressed: _addRoom,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('Novo'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.light,
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              key: _roomListKey,
              scrollController: _roomScroll,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              itemCount: layout.rooms.length,
              onReorderItem: (from, to) =>
                  _apply(layout.reorderRooms(from, to)),
              proxyDecorator: (child, _, _) => Material(
                color: Colors.transparent,
                elevation: 10,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(18),
                child: child,
              ),
              itemBuilder: (context, i) {
                final room = layout.rooms[i];
                return _RoomTile(
                  key: ValueKey(room.id),
                  index: i,
                  icon: iconForRoom(room.toRoom()),
                  name: room.name,
                  count: room.channelIds.length,
                  selected: room.id == selected,
                  dragging: _dragging,
                  accepts: (id) => layout.roomOf(id) != room.id,
                  onTap: () => setState(() => selected = room.id),
                  onDrop: (id) => _moveTo(id, room.id),
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(10),
            child: _RoomTile(
              icon: Icons.visibility_off_rounded,
              name: 'Ocultas',
              count: layout.hidden.length,
              selected: selected == _hiddenId,
              dragging: _dragging,
              muted: true,
              accepts: (id) => !layout.hidden.contains(id),
              onTap: () => setState(() => selected = _hiddenId),
              onDrop: (id) => _moveTo(id, _hiddenId),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionList() {
    final actions = layout.actions;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 10, 4),
            child: Row(
              children: [
                const Expanded(child: _SectionLabel('AÇÕES')),
                TextButton.icon(
                  onPressed: _addAction,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('Nova'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.light,
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Fixed: always first, cannot be deleted or moved.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _RoomTile(
              icon: Icons.power_settings_new_rounded,
              name: 'Apagar tudo',
              count: [
                for (final ch in c.visibleChannels)
                  if (layout.inAllOff(ch)) ch,
              ].length,
              selected: _action == _allOffId,
              dragging: null,
              locked: true,
              accepts: (_) => false,
              onTap: () => setState(() => _action = _allOffId),
              onDrop: (_) {},
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Divider(height: 1, color: AppColors.border),
          ),
          Expanded(
            child: actions.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(22, 12, 22, 0),
                    child: Text(
                      'Crie ações como "Hora do jantar" ou "Hora do filme" '
                      'no botão Nova. Elas aparecem acima dos cômodos.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    scrollController: _actionScroll,
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    itemCount: actions.length,
                    onReorderItem: (from, to) =>
                        _apply(layout.reorderActions(from, to)),
                    proxyDecorator: (child, _, _) => Material(
                      color: Colors.transparent,
                      elevation: 10,
                      shadowColor: Colors.black54,
                      borderRadius: BorderRadius.circular(18),
                      child: child,
                    ),
                    itemBuilder: (context, i) {
                      final a = actions[i];
                      return _RoomTile(
                        key: ValueKey(a.id),
                        index: i,
                        icon: iconForScene(a.icon ?? '', name: a.name),
                        name: a.name,
                        count: a.states.length,
                        selected: a.id == _action,
                        dragging: null,
                        accepts: (_) => false,
                        onTap: () => setState(() => _action = a.id),
                        onDrop: (_) {},
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionEditor() {
    final text = Theme.of(context).textTheme;
    final action = layout.action(_action);
    final sections = [
      for (final r in layout.rooms)
        if (r.channelIds.isNotEmpty) r,
    ];

    final Widget header;
    if (action == null) {
      header = Row(
        children: [
          const _IconBox(icon: Icons.power_settings_new_rounded),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Apagar tudo', style: text.headlineMedium),
                    const SizedBox(width: AppSpace.sm),
                    const Icon(
                      Icons.lock_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
                Text(
                  'Ação fixa, sempre no topo da tela. Marque o que ela desliga; '
                  'o resto fica como está, como um motor com timer.',
                  style: text.bodyMedium?.copyWith(fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          _PillButton(
            icon: Icons.lightbulb_outline_rounded,
            label: 'Só as luzes',
            onTap: () => _apply(layout.resetAllOff()),
          ),
        ],
      );
    } else {
      final on = action.states.values.where((v) => v).length;
      final off = action.states.length - on;
      header = Row(
        children: [
          _IconBox(
            icon: iconForScene(action.icon ?? '', name: action.name),
            editable: true,
            onTap: () => _pickActionIcon(action),
          ),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _renameAction(action),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          action.name,
                          style: text.headlineMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      const Icon(
                        Icons.edit_rounded,
                        size: 20,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
                Text(
                  action.states.isEmpty
                      ? 'Toque numa tecla para alternar: Acende, Apaga, Não mexe.'
                      : '$on acende${on == 1 ? '' : 'm'}  ·  '
                            '$off apaga${off == 1 ? '' : 'm'}  ·  '
                            'o resto não mexe',
                  style: text.bodyMedium?.copyWith(fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          _PillButton(
            icon: Icons.play_arrow_rounded,
            label: 'Testar',
            onTap: () {
              c.runScene(action.toScene());
              _toast('"${action.name}" executada');
            },
          ),
          const SizedBox(width: AppSpace.sm),
          _PillButton(
            icon: Icons.delete_outline_rounded,
            label: 'Excluir',
            color: AppColors.danger,
            onTap: () => _deleteAction(action),
          ),
        ],
      );
    }

    Widget chip(String id, Channel ch) => action == null
        ? _KeyChoice(
            name: c.nameOf(id),
            kind: ch.kind,
            state: layout.inAllOff(ch) ? false : null,
            onTap: () => _apply(layout.setAllOff(ch, !layout.inAllOff(ch))),
          )
        : _KeyChoice(
            name: c.nameOf(id),
            kind: ch.kind,
            state: action.states[id],
            onTap: () => _apply(
              layout.setActionState(action.id, id, switch (action.states[id]) {
                null => true,
                true => false,
                false => null,
              }),
            ),
          );

    return _Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.only(right: 8), child: header),
            const SizedBox(height: AppSpace.lg),
            Expanded(
              child: ListView(
                key: PageStorageKey(_action),
                padding: const EdgeInsets.only(right: 8, bottom: 8),
                children: [
                  for (final room in sections) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 10),
                      child: Row(
                        children: [
                          Icon(
                            iconForRoom(room.toRoom()),
                            size: 18,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: AppSpace.sm),
                          _SectionLabel(room.name.toUpperCase()),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final id in room.channelIds)
                          if (c.channel(id) case final ch?) chip(id, ch),
                      ],
                    ),
                    const SizedBox(height: AppSpace.lg),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelTab() {
    final mode = PanelModeScope.maybeOf(context);
    if (mode == null) return const SizedBox.shrink();
    final s = mode.settings;
    final text = Theme.of(context).textTheme;

    Widget section(String title, String subtitle, List<Widget> children) =>
        _Panel(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleLarge),
                const SizedBox(height: 4),
                Text(subtitle, style: text.bodyMedium?.copyWith(fontSize: 15)),
                const SizedBox(height: AppSpace.lg),
                ...children,
              ],
            ),
          ),
        );

    return ListView(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: section(
                'Protetor de tela',
                'Relógio em tela preta depois de um tempo sem uso. '
                    'Um toque volta ao painel.',
                [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final m in PanelSettings.idleChoices)
                        _Choice(
                          label: m == 0 ? 'Nunca' : '$m min',
                          selected: s.idleMinutes == m,
                          onTap: () => mode.update(s.copyWith(idleMinutes: m)),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.lg),
                  _PillButton(
                    icon: Icons.nightlight_round,
                    label: 'Mostrar agora',
                    onTap: mode.showSaver,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.lg),
            Expanded(
              child: section(
                'Brilho',
                'Em uso, segue o brilho do Android. No protetor, fica neste '
                    'nível.',
                [
                  Row(
                    children: [
                      const Icon(
                        Icons.brightness_low_rounded,
                        color: AppColors.textTertiary,
                      ),
                      Expanded(
                        child: Slider(
                          value: s.saverBrightness.clamp(0.01, 0.6),
                          min: 0.01,
                          max: 0.6,
                          activeColor: AppColors.light,
                          onChanged: (v) =>
                              mode.update(s.copyWith(saverBrightness: v)),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '${(s.saverBrightness * 100).round()}%',
                          textAlign: TextAlign.end,
                          style: text.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: s.nightDim,
                    activeThumbColor: const Color(0xFF14110A),
                    activeTrackColor: AppColors.light,
                    onChanged: (v) => mode.update(s.copyWith(nightDim: v)),
                    title: const Text('Mais escuro à noite'),
                    subtitle: const Text('Das 22h às 6h'),
                  ),
                  TextButton.icon(
                    onPressed: mode.bridge.openDisplaySettings,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Brilho adaptativo do Android'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        section(
          'Iniciar com o tablet',
          'Com o Painel Casa como tela inicial, ele abre sozinho quando o tablet '
              'liga e quando o botão Home é apertado.',
          [
            Row(
              children: [
                Icon(
                  mode.isHome
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: mode.isHome ? AppColors.plug : AppColors.textTertiary,
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    mode.isHome
                        ? 'O Painel Casa é a tela inicial do tablet.'
                        : 'Ainda não é a tela inicial. Toque em "Definir" e '
                              'escolha Painel Casa.',
                    style: text.titleMedium,
                  ),
                ),
                _PillButton(
                  icon: Icons.home_rounded,
                  label: mode.isHome ? 'Trocar' : 'Definir',
                  onTap: mode.bridge.openHomeSettings,
                ),
                const SizedBox(width: AppSpace.sm),
                _PillButton(
                  icon: Icons.settings_rounded,
                  label: 'Ajustes do Android',
                  onTap: mode.bridge.openSettings,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeys() {
    final room = selected == _hiddenId ? null : layout.room(selected);
    final ids = room?.channelIds ?? [...layout.hidden];
    final target = room?.id ?? _hiddenId;
    final text = Theme.of(context).textTheme;

    final header = room == null
        ? Row(
            children: [
              const _IconBox(icon: Icons.visibility_off_rounded),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Teclas ocultas', style: text.headlineMedium),
                    Text(
                      'Não aparecem no painel. Arraste para um cômodo, ou '
                      'toque no olho, para mostrar de novo.',
                      style: text.bodyMedium?.copyWith(fontSize: 15),
                    ),
                  ],
                ),
              ),
            ],
          )
        : Row(
            children: [
              _IconBox(
                icon: iconForRoom(room.toRoom()),
                editable: true,
                onTap: () => _pickIcon(room),
              ),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _renameRoom(room),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              room.name,
                              style: text.headlineMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          const Icon(
                            Icons.edit_rounded,
                            size: 20,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Segure uma tecla e arraste para reordenar, mover para '
                      'outro cômodo ou ocultar.',
                      style: text.bodyMedium?.copyWith(fontSize: 15),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.md),
              _PillButton(
                icon: Icons.delete_outline_rounded,
                label: 'Excluir',
                color: AppColors.danger,
                onTap: () => _deleteRoom(room),
              ),
            ],
          );

    return _Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.only(right: 8), child: header),
            const SizedBox(height: AppSpace.lg),
            Expanded(
              child: ids.isEmpty
                  ? _EmptyKeys(
                      hidden: room == null,
                      roomName: room?.name,
                      dragging: _dragging,
                      onDrop: (id) => _moveTo(id, target),
                    )
                  : ListView.builder(
                      key: _keyListKey,
                      controller: _keyScroll,
                      padding: const EdgeInsets.only(right: 8, bottom: 8),
                      itemCount: ids.length + 1,
                      itemBuilder: (context, i) {
                        if (i == ids.length) {
                          return _EndTarget(
                            dragging: _dragging,
                            accepts: (id) => room == null
                                ? !layout.hidden.contains(id)
                                : true,
                            onDrop: (id) =>
                                _moveTo(id, target, index: ids.length),
                          );
                        }
                        final id = ids[i];
                        final channel = c.channel(id);
                        if (channel == null) return const SizedBox.shrink();
                        return _KeyRow(
                          key: ValueKey(id),
                          channel: channel,
                          name: c.nameOf(id),
                          originalRoom: c.originalRoomName(id),
                          currentRoom: room?.name,
                          hidden: room == null,
                          pending: c.isPending(id),
                          dragging: _dragging,
                          onDrop: (dropped) => room == null
                              ? _moveTo(dropped, _hiddenId)
                              : _moveTo(dropped, room.id, index: i),
                          onDragStarted: () => _dragStarted(id),
                          onDragUpdate: _dragMoved,
                          onDragEnd: _dragEnded,
                          onRename: () => _renameKey(id),
                          onToggle: (on) => c.set(channel, on),
                          onHideOrShow: () =>
                              room == null ? _show(id) : _moveTo(id, _hiddenId),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- pieces -------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.customized,
    required this.tab,
    required this.onTab,
    required this.onBack,
    required this.onReset,
  });

  final bool customized;
  final int tab;
  final ValueChanged<int> onTab;
  final VoidCallback onBack;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          iconSize: 26,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surfaceHigh,
            fixedSize: const Size(52, 52),
          ),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: AppSpace.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Personalizar painel', style: text.headlineMedium),
              Text(
                'Salvo na hora, só neste tablet.',
                style: text.bodyMedium?.copyWith(fontSize: 15),
              ),
            ],
          ),
        ),
        _Tabs(
          selected: tab,
          labels: const ['Cômodos', 'Ações', 'Painel'],
          icons: const [
            Icons.grid_view_rounded,
            Icons.auto_awesome_rounded,
            Icons.tablet_rounded,
          ],
          onSelect: onTab,
        ),
        if (customized && tab == 0) ...[
          const SizedBox(width: AppSpace.md),
          _PillButton(
            icon: Icons.restart_alt_rounded,
            label: 'Restaurar',
            onTap: onReset,
          ),
        ],
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? AppColors.light.withValues(alpha: 0.16)
        : AppColors.surfaceRaised,
    shape: StadiumBorder(
      side: BorderSide(
        color: selected ? AppColors.light : AppColors.border,
        width: selected ? 1.5 : 1,
      ),
    ),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    ),
  );
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.selected,
    required this.labels,
    required this.icons,
    required this.onSelect,
  });

  final int selected;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, label) in labels.indexed)
          Material(
            color: i == selected ? AppColors.surfaceHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: () => onSelect(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      icons[i],
                      size: 18,
                      color: i == selected
                          ? AppColors.light
                          : AppColors.textTertiary,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: i == selected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// One key in an action: turned on (true), off (false) or left alone (null).
class _KeyChoice extends StatelessWidget {
  const _KeyChoice({
    required this.name,
    required this.kind,
    required this.state,
    required this.onTap,
  });

  final String name;
  final DeviceKind kind;
  final bool? state;
  final VoidCallback onTap;

  static const _offColor = Color(0xFF9FB3CF);

  @override
  Widget build(BuildContext context) {
    final light = kind == DeviceKind.light;
    final (Color color, String label, IconData mark) = switch (state) {
      true => (
        AppColors.forKind(kind),
        light ? 'Acende' : 'Liga',
        Icons.check_circle_rounded,
      ),
      false => (
        _offColor,
        light ? 'Apaga' : 'Desliga',
        Icons.do_not_disturb_on_rounded,
      ),
      null => (
        AppColors.textTertiary,
        light ? 'Não mexe' : 'Fica como está',
        Icons.circle_outlined,
      ),
    };
    final active = state != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 218,
      height: 68,
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.12) : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? color.withValues(alpha: 0.6) : AppColors.border,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  switch ((kind, state)) {
                    (DeviceKind.light, true) => Icons.lightbulb_rounded,
                    (DeviceKind.light, _) => Icons.lightbulb_outline_rounded,
                    (DeviceKind.plug, _) => Icons.power_rounded,
                    (DeviceKind.pump, _) => Icons.water_drop_rounded,
                    (DeviceKind.other, _) => Icons.toggle_on_rounded,
                  },
                  size: 20,
                  color: active ? color : AppColors.textTertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: active
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        label,
                        style: TextStyle(fontSize: 12.5, color: color),
                      ),
                    ],
                  ),
                ),
                Icon(mark, size: 22, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
      color: AppColors.textTertiary,
    ),
  );
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    super.key,
    this.index,
    required this.icon,
    required this.name,
    required this.count,
    required this.selected,
    required this.dragging,
    required this.accepts,
    required this.onTap,
    required this.onDrop,
    this.muted = false,
    this.locked = false,
  });

  /// Position in the reorderable list; null for the fixed "Ocultas" tile.
  final int? index;
  final IconData icon;
  final String name;
  final int count;
  final bool selected;
  final String? dragging;
  final bool muted;

  /// Fixed entry: shows a lock instead of a drag handle.
  final bool locked;
  final bool Function(String channelId) accepts;
  final VoidCallback onTap;
  final ValueChanged<String> onDrop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (d) => accepts(d.data),
        onAcceptWithDetails: (d) => onDrop(d.data),
        builder: (context, candidates, _) {
          final hover = candidates.isNotEmpty;
          final canDrop = dragging != null && accepts(dragging!);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: hover
                  ? AppColors.light.withValues(alpha: 0.18)
                  : selected
                  ? AppColors.surfaceHigh
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: hover
                    ? AppColors.light
                    : canDrop
                    ? AppColors.light.withValues(alpha: 0.25)
                    : selected
                    ? AppColors.border
                    : Colors.transparent,
                width: hover ? 2 : 1,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onTap,
                child: SizedBox(
                  height: 60,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(
                        icon,
                        size: 24,
                        color: muted
                            ? AppColors.textTertiary
                            : selected
                            ? AppColors.light
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      _CountBadge(count),
                      if (locked)
                        const SizedBox(
                          width: 44,
                          child: Icon(
                            Icons.lock_rounded,
                            size: 18,
                            color: AppColors.textTertiary,
                          ),
                        )
                      else if (index case final i?)
                        ReorderableDragStartListener(
                          index: i,
                          child: const SizedBox(
                            width: 44,
                            height: 60,
                            child: Icon(
                              Icons.drag_indicator_rounded,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 14),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 28),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
    child: Text(
      '$count',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({
    super.key,
    required this.channel,
    required this.name,
    required this.originalRoom,
    required this.currentRoom,
    required this.hidden,
    required this.pending,
    required this.dragging,
    required this.onDrop,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onRename,
    required this.onToggle,
    required this.onHideOrShow,
  });

  final Channel channel;
  final String name;
  final String? originalRoom;
  final String? currentRoom;
  final bool hidden;
  final bool pending;
  final String? dragging;
  final ValueChanged<String> onDrop;
  final VoidCallback onDragStarted;
  final DragUpdateCallback onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onRename;
  final ValueChanged<bool> onToggle;
  final VoidCallback onHideOrShow;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (name != channel.name) 'Smart Life: ${channel.name}',
      if (originalRoom != null && originalRoom != currentRoom) originalRoom!,
    ];
    final accent = AppColors.forKind(channel.kind);
    final on = channel.isOn && channel.online;

    Widget row({bool lifted = false}) => Container(
      height: 76,
      decoration: BoxDecoration(
        color: lifted ? AppColors.surfaceHigh : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(
          color: lifted ? AppColors.light : AppColors.border,
          width: lifted ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          // Drags at once from the handle; the rest of the row on long press.
          Draggable<String>(
            data: channel.id,
            feedback: _DragFeedback(name: name, kind: channel.kind),
            onDragStarted: onDragStarted,
            onDragUpdate: onDragUpdate,
            onDragEnd: (_) => onDragEnd(),
            onDraggableCanceled: (_, _) => onDragEnd(),
            child: const SizedBox(
              width: 48,
              height: 76,
              child: Icon(
                Icons.drag_indicator_rounded,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? accent : AppColors.surfaceHigh,
            ),
            child: Icon(
              _iconFor(channel),
              size: 20,
              color: on ? const Color(0xFF14110A) : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 17,
                    color: hidden
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
                if (details.isNotEmpty || !channel.online)
                  Text(
                    [if (!channel.online) 'Offline', ...details].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: channel.online
                          ? AppColors.textTertiary
                          : AppColors.danger,
                    ),
                  ),
              ],
            ),
          ),
          _RowIcon(
            icon: Icons.edit_rounded,
            tooltip: 'Renomear',
            onTap: onRename,
          ),
          SizedBox(
            width: 64,
            child: pending
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Switch(
                    value: channel.isOn,
                    activeThumbColor: const Color(0xFF14110A),
                    activeTrackColor: accent,
                    inactiveThumbColor: AppColors.textTertiary,
                    inactiveTrackColor: AppColors.surfaceHigh,
                    trackOutlineColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    onChanged: channel.online ? onToggle : null,
                  ),
          ),
          _RowIcon(
            icon: hidden
                ? Icons.visibility_rounded
                : Icons.visibility_off_outlined,
            tooltip: hidden ? 'Mostrar no painel' : 'Ocultar do painel',
            onTap: onHideOrShow,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != channel.id,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) {
        final hover = candidates.isNotEmpty;
        final self = dragging == channel.id;
        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: hover ? 14 : 0,
              alignment: Alignment.center,
              child: hover
                  ? Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.light,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LongPressDraggable<String>(
                data: channel.id,
                delay: const Duration(milliseconds: 250),
                feedback: _DragFeedback(name: name, kind: channel.kind),
                onDragStarted: onDragStarted,
                onDragUpdate: onDragUpdate,
                onDragEnd: (_) => onDragEnd(),
                onDraggableCanceled: (_, _) => onDragEnd(),
                childWhenDragging: Opacity(opacity: 0.3, child: row()),
                child: Opacity(opacity: self ? 0.3 : 1, child: row()),
              ),
            ),
          ],
        );
      },
    );
  }

  static IconData _iconFor(Channel c) => switch (c.kind) {
    DeviceKind.light =>
      c.isOn ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
    DeviceKind.plug => Icons.power_rounded,
    DeviceKind.pump => Icons.water_drop_rounded,
    DeviceKind.other => Icons.toggle_on_rounded,
  };
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    iconSize: 22,
    style: IconButton.styleFrom(fixedSize: const Size(52, 52)),
    icon: Icon(icon, color: AppColors.textSecondary),
  );
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.name, required this.kind});

  final String name;
  final DeviceKind kind;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Transform.rotate(
      angle: -0.02,
      child: Container(
        width: 280,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          border: Border.all(color: AppColors.light, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              kind == DeviceKind.light
                  ? Icons.lightbulb_rounded
                  : Icons.power_rounded,
              color: AppColors.forKind(kind),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Drop zone after the last key, to move a key to the end.
class _EndTarget extends StatelessWidget {
  const _EndTarget({
    required this.dragging,
    required this.accepts,
    required this.onDrop,
  });

  final String? dragging;
  final bool Function(String) accepts;
  final ValueChanged<String> onDrop;

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (d) => accepts(d.data),
    onAcceptWithDetails: (d) => onDrop(d.data),
    builder: (context, candidates, _) => AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: dragging == null ? 8 : 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: dragging == null
            ? null
            : Border.all(
                color: candidates.isNotEmpty
                    ? AppColors.light
                    : AppColors.border,
                width: candidates.isNotEmpty ? 2 : 1,
              ),
      ),
      alignment: Alignment.center,
      child: dragging == null
          ? null
          : const Text(
              'Soltar no fim da lista',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
            ),
    ),
  );
}

class _EmptyKeys extends StatelessWidget {
  const _EmptyKeys({
    required this.hidden,
    required this.roomName,
    required this.dragging,
    required this.onDrop,
  });

  final bool hidden;
  final String? roomName;
  final String? dragging;
  final ValueChanged<String> onDrop;

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onAcceptWithDetails: (d) => onDrop(d.data),
    builder: (context, candidates, _) => Container(
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: candidates.isNotEmpty ? AppColors.light : AppColors.border,
          width: candidates.isNotEmpty ? 2 : 1,
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hidden ? Icons.visibility_rounded : Icons.touch_app_rounded,
            size: 44,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            hidden
                ? 'Nenhuma tecla oculta. Tudo aparece no painel.'
                : 'Nenhuma tecla em "$roomName" ainda.\nAbra outro cômodo e '
                      'arraste as teclas até "$roomName" na lista ao lado.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, this.editable = false, this.onTap});

  final IconData icon;
  final bool editable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceHigh,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: SizedBox(
        width: 60,
        height: 60,
        child: Stack(
          children: [
            Center(child: Icon(icon, size: 30, color: AppColors.textPrimary)),
            if (editable)
              const Positioned(
                right: 6,
                bottom: 6,
                child: Icon(
                  Icons.edit_rounded,
                  size: 13,
                  color: AppColors.textTertiary,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.textPrimary;
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: fg),
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
    );
  }
}
