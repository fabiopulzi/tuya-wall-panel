import 'package:material_ui/material_ui.dart';

import '../models/models.dart';

/// Icons a room can use, by key (stored in the panel layout).
const roomIcons = <String, IconData>{
  'sofa': Icons.weekend_rounded,
  'kitchen': Icons.kitchen_rounded,
  'dining': Icons.dinner_dining_rounded,
  'bed': Icons.bed_rounded,
  'office': Icons.desktop_mac_rounded,
  'grill': Icons.outdoor_grill_rounded,
  'pool': Icons.pool_rounded,
  'garden': Icons.yard_rounded,
  'garage': Icons.garage_rounded,
  'laundry': Icons.local_laundry_service_rounded,
  'bath': Icons.bathtub_rounded,
  'stairs': Icons.stairs_rounded,
  'balcony': Icons.balcony_rounded,
  'kids': Icons.toys_rounded,
  'closet': Icons.checkroom_rounded,
  'tv': Icons.tv_rounded,
  'baby': Icons.child_friendly_rounded,
  'gym': Icons.fitness_center_rounded,
  'entrance': Icons.door_front_door_rounded,
  'deck': Icons.deck_rounded,
  'light': Icons.light_rounded,
  'home': Icons.home_rounded,
};

/// Keywords (pt-BR and en) used to guess an icon from a room name coming
/// from the Smart Life app.
const _guesses = <(String, String)>[
  ('piscina', 'pool'),
  ('pool', 'pool'),
  ('cozinha', 'kitchen'),
  ('kitchen', 'kitchen'),
  ('jantar', 'dining'),
  ('dining', 'dining'),
  ('gourmet', 'grill'),
  ('churras', 'grill'),
  ('suíte', 'bed'),
  ('suite', 'bed'),
  ('quarto', 'bed'),
  ('bedroom', 'bed'),
  ('escrit', 'office'),
  ('office', 'office'),
  ('jardim', 'garden'),
  ('quintal', 'garden'),
  ('fachada', 'garden'),
  ('externa', 'garden'),
  ('garagem', 'garage'),
  ('garage', 'garage'),
  ('lavanderia', 'laundry'),
  ('banheiro', 'bath'),
  ('lavabo', 'bath'),
  ('bath', 'bath'),
  ('escada', 'stairs'),
  ('varanda', 'balcony'),
  ('sacada', 'balcony'),
  ('brinquedo', 'kids'),
  ('closet', 'closet'),
  ('entrada', 'entrance'),
  ('hall', 'entrance'),
  ('academia', 'gym'),
  ('bebê', 'baby'),
  ('sala', 'sofa'),
  ('living', 'sofa'),
];

IconData iconForRoom(Room room) {
  if (room.icon case final key? when roomIcons.containsKey(key)) {
    return roomIcons[key]!;
  }
  final name = room.name.toLowerCase();
  for (final (word, key) in _guesses) {
    if (name.contains(word)) return roomIcons[key]!;
  }
  return Icons.home_rounded;
}

IconData iconForChannel(Channel c) => switch (c.kind) {
  DeviceKind.light =>
    c.isOn ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
  DeviceKind.plug => Icons.power_rounded,
  DeviceKind.pump => Icons.water_drop_rounded,
  DeviceKind.other => Icons.toggle_on_rounded,
};

IconData iconForScene(String key) => switch (key) {
  'night' => Icons.bedtime_rounded,
  'home' => Icons.door_front_door_rounded,
  'dinner' => Icons.restaurant_rounded,
  'party' => Icons.celebration_rounded,
  'movie' => Icons.movie_rounded,
  _ => Icons.auto_awesome_rounded,
};
