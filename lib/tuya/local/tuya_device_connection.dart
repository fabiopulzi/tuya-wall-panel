import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'local_link.dart';
import 'tuya_protocol.dart';

export 'local_link.dart' show LinkState;

/// A persistent TCP connection to one Tuya device on port 6668.
///
/// Keeps itself alive with heartbeats, reconnects with backoff, and pushes
/// every data-point change the device reports — including changes made at
/// the wall switch or by a parallel-wired key — on [updates].
class TuyaDeviceConnection implements LocalLink {
  TuyaDeviceConnection({
    required this.deviceId,
    required this.localKey,
    required String ip,
    required this.version,
    this.port = 6668,
    this.connectTimeout = const Duration(seconds: 3),
    this.requestTimeout = const Duration(seconds: 3),
    this.heartbeatEvery = const Duration(seconds: 10),
    this.socketFactory = _defaultSocket,
    // ignore: prefer_initializing_formals
  }) : _ip = ip;

  @override
  final String deviceId;
  final String localKey;
  final TuyaVersion version;
  final int port;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final Duration heartbeatEvery;
  final Future<Socket> Function(String host, int port, Duration timeout)
  socketFactory;

  String _ip;
  String get ip => _ip;

  /// Latest value of every data point seen on this connection.
  @override
  final Map<String, Object?> dps = {};

  final _updates = StreamController<Map<String, Object?>>.broadcast();
  final _states = StreamController<LinkState>.broadcast();

  /// Data points that changed, as reported by the device.
  @override
  Stream<Map<String, Object?>> get updates => _updates.stream;
  @override
  Stream<LinkState> get states => _states.stream;

  LinkState _state = LinkState.disconnected;
  LinkState get state => _state;
  @override
  bool get isConnected => _state == LinkState.connected;

  Socket? _socket;
  TuyaSession? _session;
  Uint8List _buffer = Uint8List(0);
  Timer? _heartbeat;
  Timer? _reconnect;
  int _failures = 0;
  bool _disposed = false;
  DateTime _lastRx = DateTime.now();

  /// Frames are consumed by whoever is waiting; the rest are pushes.
  final List<_Waiter> _waiters = [];
  Future<void> _queue = Future.value();

  static Future<Socket> _defaultSocket(String h, int p, Duration t) =>
      Socket.connect(h, p, timeout: t);

  /// The device moved to another IP (seen in a discovery broadcast).
  @override
  void updateIp(String ip) {
    if (ip == _ip) return;
    _ip = ip;
    if (isConnected) _drop('ip changed');
  }

  /// Connects (and negotiates a session for 3.4/3.5), then reads status.
  /// On failure, keeps retrying in the background with backoff.
  @override
  Future<void> connect() async {
    if (_disposed || _state != LinkState.disconnected) return;
    _setState(LinkState.connecting);
    try {
      final socket = await socketFactory(_ip, port, connectTimeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      // Write errors surface here, not at socket.add(): without this they
      // would be unhandled.
      unawaited(
        socket.done.then(
          (_) {},
          onError: (Object _) {
            if (identical(_socket, socket)) _drop('write failed');
          },
        ),
      );
      _buffer = Uint8List(0);
      final session = TuyaSession(
        version: version,
        localKey: localKey,
        deviceId: deviceId,
      );
      _session = session;
      socket.listen(
        _onData,
        onError: (_) => _drop('socket error'),
        onDone: () => _drop('closed by device'),
      );

      if (version.negotiatesSession) {
        final reply = _waitFor(cmd: TuyaCmd.sessKeyNegResp);
        socket.add(session.negotiationStart());
        final frame = (await reply)['frame']! as TuyaFrame;
        socket.add(session.negotiationFinish(frame));
      }

      _setState(LinkState.connected);
      _failures = 0;
      _lastRx = DateTime.now();
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(heartbeatEvery, (_) => _beat());
      await refresh();
    } catch (_) {
      _drop('connect failed');
    }
  }

  /// Asks the device for all data points and returns them.
  Future<Map<String, Object?>> refresh() => _enqueue(() async {
    final session = _requireSession();
    final cmd = session.version == TuyaVersion.v33
        ? (session.device22 ? TuyaCmd.controlNew : TuyaCmd.dpQuery)
        : TuyaCmd.dpQueryNew;
    final reply = _waitFor(cmd: cmd, needsDps: true);
    _socket!.add(session.queryStatus());
    var json = await reply;
    if (json['error'] == 'data unvalid' && session.device22) {
      // Retry once in "device22" mode.
      final retry = _waitFor(cmd: TuyaCmd.controlNew, needsDps: true);
      _socket!.add(session.queryStatus());
      json = await retry;
    }
    return Map.of(dps);
  });

  /// Sets data points, e.g. `{'1': true}`. Completes when the device
  /// acknowledges the command.
  @override
  Future<void> set(Map<String, Object?> values) => _enqueue(() async {
    final session = _requireSession();
    final cmd = session.version == TuyaVersion.v33
        ? TuyaCmd.control
        : TuyaCmd.controlNew;
    final ack = _waitFor(cmd: cmd);
    _socket!.add(session.control(values));
    await ack;
  });

  @override
  Future<void> dispose() async {
    _disposed = true;
    _reconnect?.cancel();
    _heartbeat?.cancel();
    _failWaiters('disposed');
    await _socket?.close();
    _socket?.destroy();
    await _updates.close();
    await _states.close();
  }

  // ------------------------------------------------------------ internals

  TuyaSession _requireSession() {
    final s = _session;
    if (!isConnected || s == null || _socket == null) {
      throw const SocketException('not connected');
    }
    return s;
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, Object?>> _waitFor({
    required int cmd,
    bool needsDps = false,
  }) {
    final w = _Waiter(cmd, needsDps);
    _waiters.add(w);
    return w.completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        _waiters.remove(w);
        throw TimeoutException('no reply to cmd $cmd from $deviceId');
      },
    );
  }

  void _onData(Uint8List chunk) {
    _lastRx = DateTime.now();
    _buffer = Uint8List.fromList([..._buffer, ...chunk]);
    final session = _session;
    if (session == null) return;
    while (_buffer.isNotEmpty) {
      final Unpacked r;
      try {
        r = session.unpack(_buffer);
      } on TuyaProtocolException {
        // Corrupt stream: resync from scratch.
        _drop('bad frame');
        return;
      }
      switch (r) {
        case NeedMore():
          return;
        case SkipBytes(:final count):
          _buffer = Uint8List.sublistView(_buffer, count);
        case Complete(:final frame, :final length):
          _buffer = Uint8List.sublistView(_buffer, length);
          _onFrame(session, frame);
      }
    }
  }

  void _onFrame(TuyaSession session, TuyaFrame frame) {
    if (frame.cmd == TuyaCmd.sessKeyNegResp) {
      _complete(frame.cmd, {'frame': frame});
      return;
    }
    Map<String, Object?>? json;
    try {
      json = session.decode(frame);
    } on Object {
      json = null;
    }
    final changed = <String, Object?>{};
    if (json?['dps'] case final Map<String, Object?> values) {
      for (final MapEntry(:key, :value) in values.entries) {
        if (dps[key] != value) changed[key] = value;
        dps[key] = value;
      }
    }
    _complete(frame.cmd, json ?? const {});
    if (changed.isNotEmpty && !_updates.isClosed) _updates.add(changed);
  }

  void _complete(int cmd, Map<String, Object?> json) {
    final hasDps = json['dps'] is Map;
    final w = _waiters
        .where(
          (w) =>
              w.cmd == cmd && (!w.needsDps || hasDps || json['error'] != null),
        )
        .firstOrNull;
    if (w == null) return;
    _waiters.remove(w);
    w.completer.complete(json);
  }

  void _beat() {
    final socket = _socket;
    final session = _session;
    if (socket == null || session == null) return;
    if (DateTime.now().difference(_lastRx) > heartbeatEvery * 3) {
      _drop('heartbeat timeout');
      return;
    }
    try {
      socket.add(session.heartbeat());
    } on Object {
      _drop('heartbeat failed');
    }
  }

  void _drop(String reason) {
    _heartbeat?.cancel();
    _heartbeat = null;
    final s = _socket;
    _socket = null;
    _session = null;
    s?.destroy();
    _failWaiters(reason);
    if (_state != LinkState.disconnected) _setState(LinkState.disconnected);
    if (_disposed) return;
    _failures++;
    const steps = [1, 2, 5, 10, 30];
    final wait = steps[(_failures - 1).clamp(0, steps.length - 1)];
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: wait), connect);
  }

  void _failWaiters(String reason) {
    for (final w in _waiters) {
      if (!w.completer.isCompleted) {
        w.completer.completeError(SocketException(reason));
      }
    }
    _waiters.clear();
  }

  void _setState(LinkState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }
}

class _Waiter {
  _Waiter(this.cmd, this.needsDps);
  final int cmd;
  final bool needsDps;
  final completer = Completer<Map<String, Object?>>();
}
