/// Tuya local (LAN) protocol: framing and encryption for versions 3.3, 3.4
/// and 3.5.
///
/// Wire format, reverse-engineered by the community (see tinytuya):
///
/// 55AA frames (3.1–3.4)
///   prefix 000055AA | seq u32 | cmd u32 | len u32 | [retcode u32] |
///   payload | crc32 u32 (3.3) or HMAC-SHA256 32B (3.4) | suffix 0000AA55
///   `len` counts everything after the header. Frames *from* the device carry
///   a retcode; frames we send do not.
///
/// 6699 frames (3.5)
///   prefix 00006699 | 0 u16 | seq u32 | cmd u32 | len u32 |
///   iv 12B | AES-GCM(ciphertext) | tag 16B | suffix 00009966
///   The 14 header bytes after the prefix are the GCM associated data.
///
/// Payloads are JSON. 3.3 encrypts with AES-128-ECB under the device's
/// `local_key`; 3.4/3.5 first negotiate a per-connection session key.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pointycastle/export.dart';

enum TuyaVersion {
  v33('3.3'),
  v34('3.4'),
  v35('3.5');

  const TuyaVersion(this.label);
  final String label;

  static TuyaVersion? parse(Object? v) => switch ('$v') {
    '3.3' || '3.2' => v33,
    '3.4' => v34,
    '3.5' => v35,
    _ => null,
  };

  bool get negotiatesSession => this != v33;
}

abstract final class TuyaCmd {
  static const sessKeyNegStart = 0x03;
  static const sessKeyNegResp = 0x04;
  static const sessKeyNegFinish = 0x05;
  static const control = 0x07;
  static const status = 0x08;
  static const heartBeat = 0x09;
  static const dpQuery = 0x0a;
  static const controlNew = 0x0d;
  static const dpQueryNew = 0x10;
  static const updateDps = 0x12;

  /// Commands sent without the "3.x" + 12 zero bytes version header.
  static const noVersionHeader = {
    dpQuery,
    dpQueryNew,
    updateDps,
    heartBeat,
    sessKeyNegStart,
    sessKeyNegResp,
    sessKeyNegFinish,
  };
}

const _prefix55aa = 0x000055AA;
const _suffix55aa = 0x0000AA55;
const _prefix6699 = 0x00006699;
const _suffix6699 = 0x00009966;

class TuyaFrame {
  const TuyaFrame({
    required this.seq,
    required this.cmd,
    required this.payload,
    this.retcode = 0,
  });

  final int seq;
  final int cmd;
  final int retcode;

  /// For 55AA: still encrypted (as received). For 6699: already decrypted
  /// by GCM, retcode stripped.
  final Uint8List payload;
}

class TuyaProtocolException implements Exception {
  TuyaProtocolException(this.message);
  final String message;
  @override
  String toString() => 'TuyaProtocolException: $message';
}

// ---------------------------------------------------------------- crypto

/// Local keys from the cloud are 16 ASCII characters used as raw AES keys.
Uint8List keyBytes(String localKey) {
  final bytes = Uint8List.fromList(utf8.encode(localKey));
  if (bytes.length != 16) {
    throw ArgumentError('local_key must be 16 bytes, got ${bytes.length}');
  }
  return bytes;
}

Uint8List aesEcbEncrypt(Uint8List key, Uint8List data, {bool pad = true}) {
  final input = pad ? _pkcs7Pad(data) : data;
  if (input.length % 16 != 0) {
    throw ArgumentError('ECB input must be a multiple of 16 bytes');
  }
  final cipher = ECBBlockCipher(AESEngine())..init(true, KeyParameter(key));
  final out = Uint8List(input.length);
  for (var i = 0; i < input.length; i += 16) {
    cipher.processBlock(input, i, out, i);
  }
  return out;
}

Uint8List aesEcbDecrypt(Uint8List key, Uint8List data, {bool unpad = true}) {
  if (data.isEmpty || data.length % 16 != 0) {
    throw TuyaProtocolException('ECB payload length ${data.length} invalid');
  }
  final cipher = ECBBlockCipher(AESEngine())..init(false, KeyParameter(key));
  final out = Uint8List(data.length);
  for (var i = 0; i < data.length; i += 16) {
    cipher.processBlock(data, i, out, i);
  }
  return unpad ? _pkcs7Unpad(out) : out;
}

/// Returns ciphertext followed by the 16-byte tag.
Uint8List aesGcmEncrypt(
  Uint8List key,
  Uint8List iv,
  Uint8List data, {
  Uint8List? aad,
}) {
  final gcm = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(key), 128, iv, aad ?? Uint8List(0)),
    );
  return gcm.process(data);
}

/// [data] is ciphertext followed by the 16-byte tag. Throws if the tag does
/// not authenticate.
Uint8List aesGcmDecrypt(
  Uint8List key,
  Uint8List iv,
  Uint8List data, {
  Uint8List? aad,
}) {
  final gcm = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(key), 128, iv, aad ?? Uint8List(0)),
    );
  try {
    return gcm.process(data);
  } on InvalidCipherTextException {
    throw TuyaProtocolException('GCM authentication failed');
  }
}

Uint8List hmacSha256(Uint8List key, List<int> data) =>
    Uint8List.fromList(hash.Hmac(hash.sha256, key).convert(data).bytes);

Uint8List _pkcs7Pad(Uint8List data) {
  final n = 16 - data.length % 16;
  return Uint8List.fromList([...data, ...List.filled(n, n)]);
}

Uint8List _pkcs7Unpad(Uint8List data) {
  final n = data.last;
  if (n < 1 || n > 16 || n > data.length) {
    throw TuyaProtocolException('bad padding');
  }
  return Uint8List.sublistView(data, 0, data.length - n);
}

final _random = Random.secure();
Uint8List randomBytes(int n) =>
    Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >>> 8);
  }
  return crc ^ 0xFFFFFFFF;
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

// --------------------------------------------------------------- framing

/// Packs a 55AA frame. Pass [hmacKey] for 3.4 (HMAC-SHA256 instead of
/// CRC32) and [retcode] only when simulating a device.
Uint8List pack55aa({
  required int seq,
  required int cmd,
  required Uint8List payload,
  Uint8List? hmacKey,
  int? retcode,
}) {
  final endLen = hmacKey == null ? 8 : 36;
  final body = BytesBuilder(copy: false);
  if (retcode != null) body.add(_u32(retcode));
  body.add(payload);
  final bodyBytes = body.takeBytes();

  final b = BytesBuilder(copy: false)
    ..add(_u32(_prefix55aa))
    ..add(_u32(seq))
    ..add(_u32(cmd))
    ..add(_u32(bodyBytes.length + endLen))
    ..add(bodyBytes);
  final soFar = b.toBytes();
  if (hmacKey == null) {
    b.add(_u32(_crc32(soFar)));
  } else {
    b.add(hmacSha256(hmacKey, soFar));
  }
  b.add(_u32(_suffix55aa));
  return b.takeBytes();
}

/// Packs a 6699 (AES-GCM) frame. [iv] is random unless given (tests).
Uint8List pack6699({
  required int seq,
  required int cmd,
  required Uint8List payload,
  required Uint8List key,
  int? retcode,
  Uint8List? iv,
}) {
  final plain = retcode == null
      ? payload
      : Uint8List.fromList([..._u32(retcode), ...payload]);
  final nonce = iv ?? randomBytes(12);
  final header = BytesBuilder(copy: false)
    ..add(_u32(_prefix6699))
    ..add([0, 0])
    ..add(_u32(seq))
    ..add(_u32(cmd))
    ..add(_u32(12 + plain.length + 16));
  final headerBytes = header.takeBytes();
  final sealed = aesGcmEncrypt(
    key,
    nonce,
    plain,
    aad: Uint8List.sublistView(headerBytes, 4),
  );
  return (BytesBuilder(copy: false)
        ..add(headerBytes)
        ..add(nonce)
        ..add(sealed)
        ..add(_u32(_suffix6699)))
      .takeBytes();
}

/// Result of scanning a byte buffer for one frame.
sealed class Unpacked {}

/// Not enough bytes yet; keep buffering.
class NeedMore extends Unpacked {}

/// Garbage before a prefix; drop [count] bytes and try again.
class SkipBytes extends Unpacked {
  SkipBytes(this.count);
  final int count;
}

class Complete extends Unpacked {
  Complete(this.frame, this.length);
  final TuyaFrame frame;

  /// Bytes consumed from the buffer.
  final int length;
}

/// Reads the next frame from [buf].
///
/// [key] verifies 3.4 HMACs and decrypts 3.5 frames; leave null for 3.3.
/// [hasRetcode] is true for frames coming from a device. `null` means
/// "guess" (used for 3.5 UDP broadcasts).
Unpacked unpackFrame(
  Uint8List buf, {
  Uint8List? key,
  bool useHmac = false,
  bool? hasRetcode = true,
}) {
  if (buf.length < 4) return NeedMore();
  final at55 = _indexOf(buf, const [0x00, 0x00, 0x55, 0xAA]);
  final at66 = _indexOf(buf, const [0x00, 0x00, 0x66, 0x99]);
  final start = [at55, at66].where((i) => i >= 0).fold<int>(-1, (a, b) {
    return a < 0 ? b : min(a, b);
  });
  if (start < 0) return SkipBytes(buf.length - 3);
  if (start > 0) return SkipBytes(start);

  final view = ByteData.sublistView(buf);
  if (at55 == 0) {
    if (buf.length < 16) return NeedMore();
    final seq = view.getUint32(4);
    final cmd = view.getUint32(8);
    final len = view.getUint32(12);
    if (len > 4096) throw TuyaProtocolException('frame too large ($len)');
    final total = 16 + len;
    if (buf.length < total) return NeedMore();

    final endLen = useHmac ? 36 : 8;
    final retLen = (hasRetcode ?? true) ? 4 : 0;
    if (len < endLen + retLen) throw TuyaProtocolException('frame too short');

    final signed = Uint8List.sublistView(buf, 0, total - endLen);
    if (useHmac) {
      final want = hmacSha256(key!, signed);
      final got = Uint8List.sublistView(buf, total - 36, total - 4);
      if (!_equal(want, got)) throw TuyaProtocolException('HMAC mismatch');
    } else {
      final got = view.getUint32(total - 8);
      if (got != _crc32(signed)) throw TuyaProtocolException('CRC mismatch');
    }
    final retcode = retLen == 4 ? view.getUint32(16) : 0;
    return Complete(
      TuyaFrame(
        seq: seq,
        cmd: cmd,
        retcode: retcode,
        payload: Uint8List.fromList(buf.sublist(16 + retLen, total - endLen)),
      ),
      total,
    );
  }

  // 6699
  if (buf.length < 18) return NeedMore();
  final seq = view.getUint32(6);
  final cmd = view.getUint32(10);
  final len = view.getUint32(14);
  if (len > 4096) throw TuyaProtocolException('frame too large ($len)');
  final total = 18 + len + 4;
  if (buf.length < total) return NeedMore();
  if (len < 28) throw TuyaProtocolException('frame too short');
  if (key == null) throw TuyaProtocolException('6699 frame needs a key');

  final iv = Uint8List.sublistView(buf, 18, 30);
  var plain = aesGcmDecrypt(
    key,
    iv,
    Uint8List.sublistView(buf, 30, total - 4),
    aad: Uint8List.sublistView(buf, 4, 18),
  );
  var retcode = 0;
  final strip = switch (hasRetcode) {
    true => plain.length >= 4,
    false => false,
    null => plain.length > 4 && plain[0] != 0x7B && plain[4] == 0x7B,
  };
  if (strip) {
    retcode = ByteData.sublistView(plain).getUint32(0);
    plain = Uint8List.sublistView(plain, 4);
  }
  return Complete(
    TuyaFrame(
      seq: seq,
      cmd: cmd,
      retcode: retcode,
      payload: Uint8List.fromList(plain),
    ),
    total,
  );
}

// --------------------------------------------------------------- session

/// Encryption state for one TCP connection to one device.
class TuyaSession {
  TuyaSession({
    required this.version,
    required String localKey,
    required this.deviceId,
  }) : realKey = keyBytes(localKey) {
    sessionKey = realKey;
  }

  final TuyaVersion version;
  final String deviceId;
  final Uint8List realKey;

  /// Equal to [realKey] until a 3.4/3.5 negotiation completes.
  late Uint8List sessionKey;

  /// Some 3.3 devices (often with 22-char ids) reject DP_QUERY with
  /// "data unvalid" and must be queried with CONTROL_NEW plus a dps list.
  bool device22 = false;

  int _seq = 1;
  Uint8List? _localNonce;

  Uint8List get _versionHeader => Uint8List.fromList([
    ...ascii.encode(version.label),
    ...List.filled(12, 0),
  ]);

  // ---- outgoing

  /// Frames a command: adds the version header where needed, encrypts and
  /// packs it for this protocol version.
  Uint8List encode(int cmd, Uint8List body) {
    final seq = _seq++;
    final header = !TuyaCmd.noVersionHeader.contains(cmd);
    switch (version) {
      case TuyaVersion.v33:
        final enc = aesEcbEncrypt(sessionKey, body);
        final payload = header
            ? Uint8List.fromList([..._versionHeader, ...enc])
            : enc;
        return pack55aa(seq: seq, cmd: cmd, payload: payload);
      case TuyaVersion.v34:
        final plain = header
            ? Uint8List.fromList([..._versionHeader, ...body])
            : body;
        return pack55aa(
          seq: seq,
          cmd: cmd,
          payload: aesEcbEncrypt(sessionKey, plain),
          hmacKey: sessionKey,
        );
      case TuyaVersion.v35:
        final plain = header
            ? Uint8List.fromList([..._versionHeader, ...body])
            : body;
        return pack6699(seq: seq, cmd: cmd, payload: plain, key: sessionKey);
    }
  }

  Uint8List encodeJson(int cmd, Map<String, Object?> json) =>
      encode(cmd, Uint8List.fromList(utf8.encode(jsonEncode(json))));

  String get _now => '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';

  /// Ask for every data point's current value.
  Uint8List queryStatus() => switch (version) {
    TuyaVersion.v33 when device22 => encodeJson(TuyaCmd.controlNew, {
      'devId': deviceId,
      'uid': deviceId,
      't': _now,
      'dps': {for (var i = 1; i <= 6; i++) '$i': null},
    }),
    TuyaVersion.v33 => encodeJson(TuyaCmd.dpQuery, {
      'gwId': deviceId,
      'devId': deviceId,
      'uid': deviceId,
      't': _now,
    }),
    _ => encodeJson(TuyaCmd.dpQueryNew, const {}),
  };

  /// Set data points, e.g. `{'1': true}`.
  Uint8List control(Map<String, Object?> dps) => switch (version) {
    TuyaVersion.v33 => encodeJson(TuyaCmd.control, {
      'devId': deviceId,
      'uid': deviceId,
      't': _now,
      'dps': dps,
    }),
    _ => encodeJson(TuyaCmd.controlNew, {
      'protocol': 5,
      't': int.parse(_now),
      'data': {'dps': dps},
    }),
  };

  Uint8List heartbeat() =>
      encodeJson(TuyaCmd.heartBeat, {'gwId': deviceId, 'devId': deviceId});

  // ---- incoming

  Unpacked unpack(Uint8List buf) => unpackFrame(
    buf,
    key: version == TuyaVersion.v33 ? null : sessionKey,
    useHmac: version == TuyaVersion.v34,
  );

  /// Decrypts a frame's payload to JSON. Returns null for empty payloads
  /// (acks, heartbeats). Data points are normalised to a top-level `dps`.
  Map<String, Object?>? decode(TuyaFrame frame) {
    var p = frame.payload;
    if (p.isEmpty) return null;
    final label = ascii.encode(version.label);

    switch (version) {
      case TuyaVersion.v33:
        if (_startsWith(p, label)) p = Uint8List.sublistView(p, 15);
        if (p.isEmpty) return null;
        if (p.first != 0x7B) p = aesEcbDecrypt(sessionKey, p);
      case TuyaVersion.v34:
        p = aesEcbDecrypt(sessionKey, p);
        if (_startsWith(p, label)) p = Uint8List.sublistView(p, 15);
      case TuyaVersion.v35:
        if (_startsWith(p, label)) p = Uint8List.sublistView(p, 15);
    }
    if (p.isEmpty) return null;

    final text = utf8.decode(p, allowMalformed: true);
    if (text.contains('data unvalid')) {
      device22 = true;
      return {'error': 'data unvalid'};
    }
    final json = jsonDecode(text);
    if (json is! Map<String, Object?>) return null;
    if (json['dps'] == null) {
      if (json['data'] case {'dps': final Map<String, Object?> dps}) {
        json['dps'] = dps;
      }
    }
    return json;
  }

  // ---- 3.4 / 3.5 session key negotiation

  /// Step 1: our random nonce, sent with the real local key.
  Uint8List negotiationStart() {
    _localNonce = randomBytes(16);
    sessionKey = realKey;
    return encode(TuyaCmd.sessKeyNegStart, _localNonce!);
  }

  /// Step 2 → 3: checks the device's reply and returns the FINISH frame.
  /// The session key is installed; send the returned bytes, then continue.
  Uint8List negotiationFinish(TuyaFrame reply) {
    if (reply.cmd != TuyaCmd.sessKeyNegResp) {
      throw TuyaProtocolException('unexpected cmd ${reply.cmd} in handshake');
    }
    final local = _localNonce;
    if (local == null) throw StateError('negotiationStart() not called');

    final p = version == TuyaVersion.v34
        ? aesEcbDecrypt(realKey, reply.payload)
        : reply.payload;
    if (p.length < 48) throw TuyaProtocolException('handshake reply short');
    final remote = Uint8List.fromList(p.sublist(0, 16));
    if (!_equal(hmacSha256(realKey, local), Uint8List.sublistView(p, 16, 48))) {
      throw TuyaProtocolException('handshake HMAC mismatch (wrong local key?)');
    }

    final finish = encode(
      TuyaCmd.sessKeyNegFinish,
      hmacSha256(realKey, remote),
    );

    final mixed = Uint8List.fromList([
      for (var i = 0; i < 16; i++) local[i] ^ remote[i],
    ]);
    sessionKey = version == TuyaVersion.v34
        ? aesEcbEncrypt(realKey, mixed, pad: false)
        : Uint8List.fromList(
            aesGcmEncrypt(
              realKey,
              Uint8List.sublistView(local, 0, 12),
              mixed,
            ).sublist(0, 16),
          );
    return finish;
  }
}

// --------------------------------------------------------------- helpers

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

int _indexOf(Uint8List buf, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= buf.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (buf[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

bool _startsWith(Uint8List data, List<int> prefix) {
  if (data.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (data[i] != prefix[i]) return false;
  }
  return true;
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Key used by devices to encrypt their UDP discovery broadcasts.
final Uint8List udpKey = Uint8List.fromList(
  hash.md5.convert(utf8.encode('yGAdlopoPVldABfn')).bytes,
);
