import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Minimal signed client for the Tuya OpenAPI (HMAC-SHA256 "new" signing).
///
/// Data centers:
///   Western America  https://openapi.tuyaus.com   (default for Brazil)
///   Central Europe   https://openapi.tuyaeu.com
///   China            https://openapi.tuyacn.com
///   India            https://openapi.tuyain.com
class TuyaCloudClient {
  TuyaCloudClient({
    required this.accessId,
    required this.accessSecret,
    this.baseUrl = 'https://openapi.tuyaus.com',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String accessId;
  final String accessSecret;
  final String baseUrl;
  final http.Client _http;

  String? _token;
  DateTime _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(0);
  final _random = Random.secure();

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _request('GET', path, query: query);

  Future<dynamic> post(String path, Object body) =>
      _request('POST', path, body: body);

  // ---------------------------------------------------------------- API

  /// Full device info, including `local_key`, `uid`, `category`, `online`
  /// and `status` (list of `{code, value}`).
  Future<Map<String, dynamic>> device(String id) async =>
      (await get('/v1.0/devices/$id')) as Map<String, dynamic>;

  /// Devices linked to this cloud project (paged).
  Future<List<Map<String, dynamic>>> projectDevices() async {
    final out = <Map<String, dynamic>>[];
    String? lastId;
    while (true) {
      final result = await get(
        '/v2.0/cloud/thing/device',
        query: {'page_size': '20', 'last_id': ?lastId},
      );
      final page = (result as List).cast<Map<String, dynamic>>();
      out.addAll(page);
      if (page.length < 20) break;
      lastId = page.last['id'] as String;
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> homes(String uid) async =>
      ((await get('/v1.0/users/$uid/homes')) as List)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> rooms(int homeId) async {
    final result = await get('/v1.0/homes/$homeId/rooms') as Map;
    return (result['rooms'] as List? ?? const []).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> roomDevices(
    int homeId,
    int roomId,
  ) async => ((await get('/v1.0/homes/$homeId/rooms/$roomId/devices')) as List)
      .cast<Map<String, dynamic>>();

  /// Names given to each gang of a multi-gang switch in the Smart Life app.
  Future<Map<String, String>> subSwitchNames(String deviceId) async {
    final result = await get('/v1.0/devices/$deviceId/multiple-name');
    return {
      for (final e in (result as List).cast<Map<String, dynamic>>())
        e['identifier'] as String: e['name'] as String,
    };
  }

  Future<List<Map<String, dynamic>>> status(String deviceId) async =>
      ((await get('/v1.0/devices/$deviceId/status')) as List)
          .cast<Map<String, dynamic>>();

  Future<void> sendCommand(String deviceId, String code, Object value) =>
      post('/v1.0/devices/$deviceId/commands', {
        'commands': [
          {'code': code, 'value': value},
        ],
      });

  // ------------------------------------------------------------ plumbing

  Future<void> _ensureToken() async {
    if (_token != null &&
        DateTime.now().isBefore(
          _tokenExpiry.subtract(const Duration(minutes: 2)),
        )) {
      return;
    }
    final result = await _request(
      'GET',
      '/v1.0/token',
      query: {'grant_type': '1'},
      authenticated: false,
    ) as Map<String, dynamic>;
    _token = result['access_token'] as String;
    _tokenExpiry = DateTime.now().add(
      Duration(seconds: (result['expire_time'] as num).toInt()),
    );
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool authenticated = true,
  }) async {
    if (authenticated) await _ensureToken();

    final sortedQuery = query == null
        ? ''
        : (query.keys.toList()..sort()).map((k) => '$k=${query[k]}').join('&');
    final urlPath = sortedQuery.isEmpty ? path : '$path?$sortedQuery';
    final bodyText = body == null ? '' : jsonEncode(body);

    final t = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _nonce();
    final contentHash = sha256.convert(utf8.encode(bodyText)).toString();
    final stringToSign = '$method\n$contentHash\n\n$urlPath';
    final token = authenticated ? _token! : '';
    final sign = Hmac(sha256, utf8.encode(accessSecret))
        .convert(utf8.encode('$accessId$token$t$nonce$stringToSign'))
        .toString()
        .toUpperCase();

    final headers = {
      'client_id': accessId,
      'sign': sign,
      'sign_method': 'HMAC-SHA256',
      't': t,
      'nonce': nonce,
      if (authenticated) 'access_token': token,
      'Content-Type': 'application/json',
    };

    final uri = Uri.parse('$baseUrl$urlPath');
    final response = method == 'POST'
        ? await _http.post(uri, headers: headers, body: bodyText)
        : await _http.get(uri, headers: headers);

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['success'] != true) {
      // 1010 = token invalid: drop it so the next call fetches a new one.
      if (json['code'] == 1010) _token = null;
      throw TuyaApiException(json['code'], json['msg']?.toString());
    }
    return json['result'];
  }

  String _nonce() =>
      List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();
}

class TuyaApiException implements Exception {
  TuyaApiException(this.code, this.message);

  final Object? code;
  final String? message;

  @override
  String toString() => 'Tuya API error $code: $message';
}
