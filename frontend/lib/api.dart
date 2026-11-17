import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final String message;
  final int status;
  final String? code;
  ApiException(this.message, this.status, {this.code});
  @override
  String toString() => message;
}

String uid() {
  final random = Random.secure();
  return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
}

String money(num fils) => (fils / 1000).toStringAsFixed(3);
int parseMoney(String value) {
  if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(value.trim())) {
    throw Exception('Enter an amount with up to three decimals.');
  }
  final parts = value.trim().split('.');
  return int.parse(parts[0]) * 1000 +
      int.parse((parts.length > 1 ? parts[1] : '').padRight(3, '0'));
}

String today() => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 3))
    .toIso8601String()
    .substring(0, 10);
String displayDate(dynamic value) {
  final date = DateTime.tryParse('$value');
  if (date == null) return '$value';
  return date
      .toUtc()
      .add(const Duration(hours: 3))
      .toIso8601String()
      .substring(0, 16)
      .replaceAll('T', ' ');
}

class Api {
  static int _sessionEpoch = 0;
  static int get sessionEpoch => _sessionEpoch;
  static void Function(String)? onShiftBlocked;
  static Future<void>? _sessionCleanup;
  static void queueSessionLogout() {
    final pending = post(
      'auth/logout',
      {},
    ).then<void>((_) {}).catchError((Object _) {});
    _sessionCleanup = pending;
    unawaitedCleanup(pending);
  }

  static void unawaitedCleanup(Future<void> pending) {
    pending.whenComplete(() {
      if (identical(_sessionCleanup, pending)) _sessionCleanup = null;
    });
  }

  static void invalidatePendingRequests() => _sessionEpoch++;
  static http.Client client = http.Client();
  static const root = String.fromEnvironment('API_URL');
  static Uri uri(String path) =>
      Uri.parse(root.isEmpty ? Uri.base.origin : root).resolve('/api/$path');
  static Future<dynamic> get(String path) async {
    final epoch = _sessionEpoch;
    return checkedDecode(await client.get(uri(path)), epoch);
  }

  static Future<dynamic> post(String path, Json data) async {
    if (path == 'auth/login') await _sessionCleanup;
    final epoch = _sessionEpoch;
    return checkedDecode(
      await client.post(
        uri(path),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ),
      epoch,
    );
  }

  static dynamic checkedDecode(http.Response response, int epoch) {
    if (epoch != _sessionEpoch) {
      throw ApiException(
        'This request belongs to an earlier session.',
        401,
        code: 'STALE_SESSION',
      );
    }
    return decode(response);
  }

  static dynamic decode(http.Response response) {
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw Exception(
        'The server did not respond correctly. Please try again.',
      );
    }
    if (response.statusCode >= 400) {
      if (data is Map && data['code'] == 'SHIFT_BLOCKED') {
        onShiftBlocked?.call('${data['error']}');
      }
      throw ApiException(
        data is Map ? data['error'] ?? 'Request failed.' : 'Request failed.',
        response.statusCode,
        code: data is Map ? data['code']?.toString() : null,
      );
    }
    return data;
  }

  static Future<Json> upload(
    String branch,
    List<int> bytes,
    String type,
    String name,
  ) async {
    final epoch = _sessionEpoch;
    return Map<String, dynamic>.from(
      checkedDecode(
        await client.post(
          uri('documents?branch=$branch'),
          headers: {
            'Content-Type': type,
            'X-File-Name': Uri.encodeComponent(name),
          },
          body: bytes,
        ),
        epoch,
      ),
    );
  }
}
