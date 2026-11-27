import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../state/home_controller.dart';
import 'room_sheet.dart';
import 'widgets/header.dart';
import 'widgets/room_card.dart';
import 'widgets/scene_bar.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.controller});

  final HomeController controller;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  HomeController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.failures.addListener(_showFailure);
  }

  @override
  void dispose() {
    c.failures.removeListener(_showFailure);
    super.dispose();
  }

  void _showFailure() {
    final message = c.failures.value;
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    c.failures.value = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DashboardHeader(controller: c),
              const SizedBox(height: AppSpace.xl),
              Expanded(
                child: ListenableBuilder(
                  listenable: c,
                  builder: (context, _) {
                    if (c.loading && c.rooms.isEmpty) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.textSecondary,
                        ),
                      );
                    }
                    if (c.error != null && c.rooms.isEmpty) {
                      return _ErrorState(error: c.error!, onRetry: c.load);
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SceneBar(scenes: c.scenes, onRun: c.runScene),
                        if (c.scenes.isNotEmpty)
                          const SizedBox(height: AppSpace.xl),
                        Expanded(child: _RoomGrid(controller: c)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomGrid extends StatelessWidget {
  const _RoomGrid({required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    final rooms = controller.rooms;
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 200,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: rooms.length,
      itemBuilder: (context, i) {
        final room = rooms[i];
        return RoomCard(
          room: room,
          channels: controller.channelsIn(room.id),
          onOpen: () =>
              showRoomSheet(context, controller: controller, room: room),
          onToggleLights: (on) => controller.setRoomLights(room.id, on),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            'Não consegui carregar a casa',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpace.sm),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: AppSpace.xl),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }
}
