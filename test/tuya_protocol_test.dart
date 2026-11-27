import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuya_wall_panel/tuya/local/tuya_discovery.dart';
import 'package:tuya_wall_panel/tuya/local/tuya_protocol.dart';

Uint8List hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

String toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('crypto primitives', () {
    test('AES-128 matches the FIPS-197 vector', () {
      final out = aesEcbEncrypt(
        hex('000102030405060708090a0b0c0d0e0f'),
        hex('00112233445566778899aabbccddeeff'),
        pad: false,
      );
      expect(toHex(out), '69c4e0d86a7b0430d8cdb78070b4c55a');
    });

    test('AES-GCM matches the McGrew–Viega test case 2', () {
      final out = aesGcmEncrypt(Uint8List(16), Uint8List(12), Uint8List(16));
      expect(toHex(out.sublist(0, 16)), '0388dace60b6a392f328c2b971b2fe78');
      expect(toHex(out.sublist(16)), 'ab6e47d42cec13bdf53a67b21257bddf');
    });

    test('ECB padding round-trips any length', () {
      final key = keyBytes('0123456789abcdef');
      for (final n in [0, 1, 15, 16, 17, 40]) {
        final data = Uint8List.fromList(List.generate(n, (i) => i));
        expect(aesEcbDecrypt(key, aesEcbEncrypt(key, data)), data);
      }
    });

    test('tampered GCM data is rejected', () {
      final key = keyBytes('0123456789abcdef');
      final iv = Uint8List(12);
      final sealed = aesGcmEncrypt(key, iv, Uint8List.fromList([1, 2, 3]));
      sealed[0] ^= 1;
      expect(
        () => aesGcmDecrypt(key, iv, sealed),
        throwsA(isA<TuyaProtocolException>()),
      );
    });

    test('UDP key is md5 of the well-known string', () {
      expect(toHex(udpKey), '6c1ec8e2bb9bb59ab50b0daf649b410a');
    });
  });

  group('framing', () {
    final key = keyBytes('0123456789abcdef');
    final body = Uint8List.fromList(utf8.encode('{"a":1}'));

    test('55AA with CRC round-trips and checks the CRC', () {
      final f = pack55aa(seq: 7, cmd: 10, payload: body, retcode: 0);
      final r = unpackFrame(f) as Complete;
      expect(r.length, f.length);
      expect(r.frame.seq, 7);
      expect(r.frame.cmd, 10);
      expect(r.frame.payload, body);

      f[f.length - 6] ^= 0xFF; // flip a CRC byte
      expect(() => unpackFrame(f), throwsA(isA<TuyaProtocolException>()));
    });

    test('55AA with HMAC (3.4) verifies the key', () {
      final f = pack55aa(
        seq: 1,
        cmd: 8,
        payload: body,
        retcode: 0,
        hmacKey: key,
      );
      expect(
        (unpackFrame(f, key: key, useHmac: true) as Complete).frame.payload,
        body,
      );
      expect(
        () => unpackFrame(f, key: keyBytes('fedcba9876543210'), useHmac: true),
        throwsA(isA<TuyaProtocolException>()),
      );
    });

    test('6699 (3.5) round-trips and strips the retcode', () {
      final f = pack6699(seq: 3, cmd: 16, payload: body, key: key, retcode: 0);
      final r = unpackFrame(f, key: key) as Complete;
      expect(r.frame.payload, body);
      expect(r.length, f.length);
    });

    test('partial input asks for more; leading garbage is skipped', () {
      final f = pack55aa(seq: 1, cmd: 9, payload: body, retcode: 0);
      expect(unpackFrame(Uint8List.sublistView(f, 0, 10)), isA<NeedMore>());
      final noisy = Uint8List.fromList([1, 2, 3, ...f]);
      expect((unpackFrame(noisy) as SkipBytes).count, 3);
    });

    test('two frames in one chunk are read one after the other', () {
      final a = pack55aa(seq: 1, cmd: 9, payload: Uint8List(0), retcode: 0);
      final b = pack55aa(seq: 2, cmd: 8, payload: body, retcode: 0);
      final both = Uint8List.fromList([...a, ...b]);
      final first = unpackFrame(both) as Complete;
      final second =
          unpackFrame(Uint8List.sublistView(both, first.length)) as Complete;
      expect([first.frame.seq, second.frame.seq], [1, 2]);
    });
  });

  group('3.3 session', () {
    const id = 'bf00000000000000test01';
    final session = TuyaSession(
      version: TuyaVersion.v33,
      localKey: '0123456789abcdef',
      deviceId: id,
    );

    test('control frames carry the version header and encrypted JSON', () {
      final r = unpackFrame(
        session.control({'1': true}),
        hasRetcode: false,
      ) as Complete;
      expect(r.frame.cmd, TuyaCmd.control);
      expect(ascii.decode(r.frame.payload.sublist(0, 3)), '3.3');
      final json = jsonDecode(
        utf8.decode(
          aesEcbDecrypt(session.realKey, r.frame.payload.sublist(15)),
        ),
      );
      expect(json['devId'], id);
      expect(json['dps'], {'1': true});
    });

    test('status queries have no version header', () {
      final r =
          unpackFrame(session.queryStatus(), hasRetcode: false) as Complete;
      expect(r.frame.cmd, TuyaCmd.dpQuery);
      final json = jsonDecode(
        utf8.decode(aesEcbDecrypt(session.realKey, r.frame.payload)),
      );
      expect(json['gwId'], id);
    });

    test('decodes device replies with and without the header', () {
      final enc = aesEcbEncrypt(
        session.realKey,
        Uint8List.fromList(utf8.encode('{"dps":{"1":true}}')),
      );
      final plain = TuyaFrame(seq: 1, cmd: 10, payload: enc);
      final withHeader = TuyaFrame(
        seq: 2,
        cmd: 8,
        payload: Uint8List.fromList([
          ...ascii.encode('3.3'),
          ...List.filled(12, 0),
          ...enc,
        ]),
      );
      expect(session.decode(plain)!['dps'], {'1': true});
      expect(session.decode(withHeader)!['dps'], {'1': true});
    });

    test('"data unvalid" switches to device22 mode', () {
      final s = TuyaSession(
        version: TuyaVersion.v33,
        localKey: '0123456789abcdef',
        deviceId: id,
      );
      final enc = aesEcbEncrypt(
        s.realKey,
        Uint8List.fromList(utf8.encode('data unvalid')),
      );
      s.decode(TuyaFrame(seq: 1, cmd: 10, payload: enc));
      expect(s.device22, isTrue);
      final r = unpackFrame(s.queryStatus(), hasRetcode: false) as Complete;
      expect(r.frame.cmd, TuyaCmd.controlNew);
    });
  });

  group('discovery broadcasts', () {
    test('decodes an encrypted 6667 broadcast', () {
      final json = {'ip': '10.0.0.117', 'gwId': 'abc', 'version': '3.3'};
      final enc = aesEcbEncrypt(
        udpKey,
        Uint8List.fromList(utf8.encode(jsonEncode(json))),
      );
      final frame = pack55aa(seq: 0, cmd: 0x13, payload: enc, retcode: 0);
      expect(TuyaDiscovery.decodeBroadcast(frame), json);
    });

    test('decodes a 3.5 broadcast on port 7000', () {
      final json = {'ip': '10.0.0.9', 'gwId': 'xyz', 'version': '3.5'};
      final frame = pack6699(
        seq: 0,
        cmd: 0x13,
        payload: Uint8List.fromList(utf8.encode(jsonEncode(json))),
        key: udpKey,
      );
      expect(TuyaDiscovery.decodeBroadcast(frame), json);
    });

    test('ignores noise', () {
      expect(
        TuyaDiscovery.decodeBroadcast(Uint8List.fromList([1, 2, 3])),
        isNull,
      );
    });
  });
}
