import 'dart:math';

import '../models/models.dart';
import 'home_repository.dart';

/// Fictional house with ~40 outputs, used to build and review the layout
/// without touching real devices.
class DemoRepository implements HomeRepository {
  DemoRepository({this.latency = const Duration(milliseconds: 180)});

  final Duration latency;
  final _random = Random(7);

  @override
  Future<HomeSnapshot> load() async {
    await Future<void>.delayed(latency);

    const rooms = [
      Room(id: 'sala', name: 'Sala de estar'),
      Room(id: 'cozinha', name: 'Cozinha'),
      Room(id: 'jantar', name: 'Sala de jantar'),
      Room(id: 'suite', name: 'Suíte master'),
      Room(id: 'quarto', name: 'Quarto de hóspedes'),
      Room(id: 'escritorio', name: 'Escritório'),
      Room(id: 'gourmet', name: 'Varanda gourmet'),
      Room(id: 'piscina', name: 'Piscina'),
      Room(id: 'jardim', name: 'Jardim e fachada'),
      Room(id: 'garagem', name: 'Garagem'),
      Room(id: 'lavanderia', name: 'Lavanderia'),
      Room(id: 'banheiros', name: 'Banheiros'),
    ];

    Channel light(
      String room,
      String dev,
      int gang,
      String name, {
      bool on = false,
    }) => Channel(
      deviceId: dev,
      code: 'switch_$gang',
      name: name,
      kind: DeviceKind.light,
      roomId: room,
      isOn: on,
    );

    Channel plug(String room, String dev, String name, {bool on = false}) =>
        Channel(
          deviceId: dev,
          code: 'switch_1',
          name: name,
          kind: DeviceKind.plug,
          roomId: room,
          isOn: on,
        );

    final channels = [
      light('sala', 'sw_sala_1', 1, 'Lustre', on: true),
      light('sala', 'sw_sala_1', 2, 'Spots do teto', on: true),
      light('sala', 'sw_sala_1', 3, 'Fita de LED'),
      plug('sala', 'pl_sala_abajur', 'Abajur', on: true),
      light('cozinha', 'sw_coz_1', 1, 'Teto'),
      light('cozinha', 'sw_coz_1', 2, 'Bancada', on: true),
      plug('cozinha', 'pl_coz_cafe', 'Cafeteira'),
      light('jantar', 'sw_jantar', 1, 'Pendente da mesa'),
      light('jantar', 'sw_jantar', 2, 'Sanca'),
      light('suite', 'sw_suite_1', 1, 'Teto'),
      light('suite', 'sw_suite_1', 2, 'Cabeceira'),
      light('suite', 'sw_suite_2', 1, 'Closet'),
      plug('suite', 'pl_suite_ar', 'Umidificador'),
      light('quarto', 'sw_quarto', 1, 'Teto'),
      light('quarto', 'sw_quarto', 2, 'Abajur'),
      light('escritorio', 'sw_escr', 1, 'Teto', on: true),
      light('escritorio', 'sw_escr', 2, 'Luminária da mesa', on: true),
      plug('escritorio', 'pl_escr_pc', 'Computador', on: true),
      light('gourmet', 'sw_gourmet', 1, 'Pendentes'),
      light('gourmet', 'sw_gourmet', 2, 'Churrasqueira'),
      light('gourmet', 'sw_gourmet', 3, 'Varal de luz'),
      const Channel(
        deviceId: 'pump_piscina',
        code: 'switch_1',
        name: 'Filtro da piscina',
        kind: DeviceKind.pump,
        roomId: 'piscina',
        isOn: true,
      ),
      light('piscina', 'sw_piscina', 1, 'Luz da piscina'),
      light('piscina', 'sw_piscina', 2, 'Cascata'),
      light('jardim', 'sw_jardim', 1, 'Jardim frontal'),
      light('jardim', 'sw_jardim', 2, 'Fachada'),
      light('jardim', 'sw_jardim', 3, 'Muro'),
      light('jardim', 'sw_jardim_2', 1, 'Portão'),
      light('garagem', 'sw_garagem', 1, 'Garagem'),
      plug('garagem', 'pl_garagem', 'Carregador'),
      light('lavanderia', 'sw_lav', 1, 'Lavanderia'),
      plug('lavanderia', 'pl_lav', 'Secadora'),
      light('banheiros', 'sw_banh', 1, 'Banheiro social'),
      light('banheiros', 'sw_banh', 2, 'Lavabo'),
      light('banheiros', 'sw_banh_suite', 1, 'Banheiro da suíte'),
      light('banheiros', 'sw_banh_suite', 2, 'Espelho da suíte'),
    ];

    final scenes = [
      Scene(
        id: 'boa_noite',
        name: 'Boa noite',
        icon: 'night',
        actions: {
          for (final c in channels)
            if (c.kind == DeviceKind.light) c.id: false,
          'sw_suite_1:switch_2': true,
        },
      ),
      Scene(
        id: 'chegando',
        name: 'Chegando',
        icon: 'home',
        actions: {
          'sw_jardim_2:switch_1': true,
          'sw_garagem:switch_1': true,
          'sw_sala_1:switch_2': true,
        },
      ),
      Scene(
        id: 'jantar',
        name: 'Jantar',
        icon: 'dinner',
        actions: {
          'sw_jantar:switch_1': true,
          'sw_jantar:switch_2': true,
          'sw_sala_1:switch_1': false,
          'sw_sala_1:switch_3': true,
        },
      ),
      Scene(
        id: 'festa',
        name: 'Área externa',
        icon: 'party',
        actions: {
          'sw_gourmet:switch_1': true,
          'sw_gourmet:switch_3': true,
          'sw_piscina:switch_1': true,
          'sw_piscina:switch_2': true,
          'sw_jardim:switch_1': true,
        },
      ),
    ];

    return HomeSnapshot(
      homeName: 'Casa',
      rooms: rooms,
      channels: channels,
      scenes: scenes,
    );
  }

  @override
  Future<void> setChannel(Channel channel, bool on) async {
    await Future<void>.delayed(
      latency + Duration(milliseconds: _random.nextInt(120)),
    );
  }

  @override
  Future<List<Channel>> refresh(List<Channel> current) async => current;

  @override
  Stream<List<Channel>> get pushes => const Stream.empty();

  @override
  Stream<HomeSnapshot> get snapshots => const Stream.empty();
}
