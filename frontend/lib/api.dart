import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, this.status);
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
  static http.Client client = http.Client();
  static const root = String.fromEnvironment('API_URL');
  static Uri uri(String path) =>
      Uri.parse(root.isEmpty ? Uri.base.origin : root).resolve('/api/$path');
  static Future<dynamic> get(String path) async =>
      decode(await client.get(uri(path)));
  static Future<dynamic> post(String path, Json data) async => decode(
    await client.post(
      uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    ),
  );
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
      throw ApiException(
        data is Map ? data['error'] ?? 'Request failed.' : 'Request failed.',
        response.statusCode,
      );
    }
    return data;
  }

  static Future<Json> upload(
    String branch,
    List<int> bytes,
    String type,
    String name,
  ) async => Map<String, dynamic>.from(
    decode(
      await client.post(
        uri('documents?branch=$branch'),
        headers: {
          'Content-Type': type,
          'X-File-Name': Uri.encodeComponent(name),
        },
        body: bytes,
      ),
    ),
  );
}
