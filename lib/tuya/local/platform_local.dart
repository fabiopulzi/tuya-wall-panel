// LAN control needs raw sockets, which browsers do not have. The web
// preview gets `null` and stays cloud-only.
export 'platform_local_stub.dart' if (dart.library.io) 'platform_local_io.dart';
