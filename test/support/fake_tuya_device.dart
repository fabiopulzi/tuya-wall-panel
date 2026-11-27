import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tuya_wall_panel/tuya/local/tuya_protocol.dart';

/// A minimal Tuya device on a loopback socket, written from the device's
/// side of the protocol, to exercise the client end to end.
class FakeTuyaDevice {
  FakeTuyaDevice({
    required this.version,
    required this.localKey,
    required this.deviceId,
    Map<String, Object?>? dps,
    this.ackDelay = Duration.zero,
    this.silent = false,
  }) : dps = dps ?? {'1': false, '2': true};

  final TuyaVersion version;
  final String localKey;
  final String deviceId;
  final Map<String, Object?> dps;
  final Duration ackDelay;

  /// Accepts connections but never answers (unreachable-ish device).
  final bool silent;

  late ServerSocket _server;
  final List<Socket> _clients = [];
  final List<Map<String, Object?>> controls = [];
  int get port => _server.port;

  Uint8List get _real => keyBytes(localKey);

  Future<void> start() => startOn(0);

  Future<void> startOn(int port) async {
    _server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: true,
    );
    _server.listen(_serve);
  }

  Future<void> stop() async {
    for (final c in [..._clients]) {
      c.destroy();
    }
    _clients.clear();
    await _server.close();
  }

  /// Simulates someone pressing the wall switch.
  void press(String dp, bool value) {
    dps[dp] = value;
    for (final c in [..._clients]) {
      _send(c, _ClientState.of(c), TuyaCmd.status, {
        'devId': deviceId,
        'dps': {dp: value},
        't': 0,
      }, header: true);
    }
  }

  void _serve(Socket socket) {
    _clients.add(socket);
    final state = _ClientState.of(socket)..key = _real;
    var buf = Uint8List(0);
    socket.listen(
      (chunk) {
        buf = Uint8List.fromList([...buf, ...chunk]);
        while (true) {
          final Unpacked r;
          try {
            r = unpackFrame(
              buf,
              key: version == TuyaVersion.v33 ? null : state.key,
              useHmac: version == TuyaVersion.v34,
              hasRetcode: false,
            );
          } on TuyaProtocolException {
            socket.destroy(); // Real devices hang up on bad frames.
            return;
          }
          if (r is! Complete) {
            if (r is SkipBytes) {
              buf = Uint8List.sublistView(buf, r.count);
              continue;
            }
            return;
          }
          buf = Uint8List.sublistView(buf, r.length);
          if (!silent) _handle(socket, state, r.frame);
        }
      },
      onDone: () => _clients.remove(socket),
      onError: (_) {},
    );
    socket.done.ignore();
  }

  Uint8List _decrypt(_ClientState s, Uint8List p) {
    final label = ascii.encode(version.label);
    bool hasHeader(Uint8List d) =>
        d.length >= 15 &&
        d[0] == label[0] &&
        d[1] == label[1] &&
        d[2] == label[2];
    switch (version) {
      case TuyaVersion.v33:
        if (hasHeader(p)) p = Uint8List.sublistView(p, 15);
        return aesEcbDecrypt(s.key, p);
      case TuyaVersion.v34:
        final d = aesEcbDecrypt(s.key, p);
        return hasHeader(d) ? Uint8List.sublistView(d, 15) : d;
      case TuyaVersion.v35:
        return hasHeader(p) ? Uint8List.sublistView(p, 15) : p;
    }
  }

  void _handle(Socket socket, _ClientState s, TuyaFrame f) {
    switch (f.cmd) {
      case TuyaCmd.sessKeyNegStart:
        final local = version == TuyaVersion.v34
            ? aesEcbDecrypt(_real, f.payload)
            : f.payload;
        s.localNonce = Uint8List.fromList(local);
        s.remoteNonce = randomBytes(16);
        final body = Uint8List.fromList([
          ...s.remoteNonce,
          ...hmacSha256(_real, local),
        ]);
        _sendRaw(socket, s, TuyaCmd.sessKeyNegResp, body);
      case TuyaCmd.sessKeyNegFinish:
        final p = version == TuyaVersion.v34
            ? aesEcbDecrypt(_real, f.payload)
            : f.payload;
        if (!_eq(p, hmacSha256(_real, s.remoteNonce))) {
          socket.destroy();
          return;
        }
        final mixed = Uint8List.fromList([
          for (var i = 0; i < 16; i++) s.localNonce[i] ^ s.remoteNonce[i],
        ]);
        s.key = version == TuyaVersion.v34
            ? aesEcbEncrypt(_real, mixed, pad: false)
            : Uint8List.fromList(
                aesGcmEncrypt(
                  _real,
                  Uint8List.sublistView(s.localNonce, 0, 12),
                  mixed,
                ).sublist(0, 16),
              );
      case TuyaCmd.dpQuery || TuyaCmd.dpQueryNew:
        _send(socket, s, f.cmd, {'devId': deviceId, 'dps': dps});
      case TuyaCmd.control || TuyaCmd.controlNew:
        final json = jsonDecode(
          utf8.decode(_decrypt(s, f.payload)),
        ) as Map<String, Object?>;
        final values =
            (json['dps'] ?? (json['data']! as Map)['dps'])
                as Map<String, Object?>;
        controls.add(values);
        Future<void>.delayed(ackDelay, () {
          dps.addAll(values);
          _sendRaw(socket, s, f.cmd, Uint8List(0)); // ack
          _send(socket, s, TuyaCmd.status, {
            'devId': deviceId,
            'dps': values,
          }, header: true);
        });
      case TuyaCmd.heartBeat:
        _sendRaw(socket, s, TuyaCmd.heartBeat, Uint8List(0));
    }
  }

  void _send(
    Socket socket,
    _ClientState s,
    int cmd,
    Map<String, Object?> json, {
    bool header = false,
  }) {
    final body = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final label = [...ascii.encode(version.label), ...List.filled(12, 0)];
    switch (version) {
      case TuyaVersion.v33:
        final enc = aesEcbEncrypt(s.key, body);
        _frame(
          socket,
          s,
          cmd,
          header ? Uint8List.fromList([...label, ...enc]) : enc,
        );
      case TuyaVersion.v34:
        _frame(
          socket,
          s,
          cmd,
          aesEcbEncrypt(
            s.key,
            header ? Uint8List.fromList([...label, ...body]) : body,
          ),
        );
      case TuyaVersion.v35:
        _frame(
          socket,
          s,
          cmd,
          header ? Uint8List.fromList([...label, ...body]) : body,
        );
    }
  }

  /// Handshake replies and acks: no JSON, but 3.4 still encrypts.
  void _sendRaw(Socket socket, _ClientState s, int cmd, Uint8List body) {
    if (version == TuyaVersion.v34 && body.isNotEmpty) {
      _frame(socket, s, cmd, aesEcbEncrypt(s.key, body));
    } else {
      _frame(socket, s, cmd, body);
    }
  }

  void _frame(Socket socket, _ClientState s, int cmd, Uint8List payload) {
    final seq = s.seq++;
    socket.add(switch (version) {
      TuyaVersion.v33 => pack55aa(
        seq: seq,
        cmd: cmd,
        payload: payload,
        retcode: 0,
      ),
      TuyaVersion.v34 => pack55aa(
        seq: seq,
        cmd: cmd,
        payload: payload,
        retcode: 0,
        hmacKey: s.key,
      ),
      TuyaVersion.v35 => pack6699(
        seq: seq,
        cmd: cmd,
        payload: payload,
        retcode: 0,
        key: s.key,
      ),
    });
  }

  static bool _eq(List<int> a, List<int> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
}

class _ClientState {
  static final _states = Expando<_ClientState>();
  static _ClientState of(Socket s) => _states[s] ??= _ClientState();

  late Uint8List key;
  Uint8List localNonce = Uint8List(0);
  Uint8List remoteNonce = Uint8List(0);
  int seq = 1;
}
