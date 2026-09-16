import 'dart:convert';

import 'package:http/http.dart' as http;

/// Cross-platform Firebase Realtime Database client.
///
/// It deliberately uses Firebase's REST endpoint instead of the desktop C++
/// SDK, avoiding native EventChannel/thread crashes on Windows.
class RealtimeDatabaseRest {
  RealtimeDatabaseRest._();
  static final instance = RealtimeDatabaseRest._();

  static const _baseUrl = 'https://time-care-642b1-default-rtdb.firebaseio.com';
  static const _timeout = Duration(seconds: 15);

  Uri _uri(String path) => Uri.parse('$_baseUrl/${path.replaceAll(RegExp(r'^/+|/+$'), '')}.json');

  Future<Object?> get(String path) async {
    final response = await http.get(_uri(path)).timeout(_timeout);
    _ensureSuccess(response);
    return jsonDecode(response.body);
  }

  Future<String> push(String path, Map<String, Object?> value) async {
    final response = await http
        .post(_uri(path), body: jsonEncode(value))
        .timeout(_timeout);
    _ensureSuccess(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['name'] as String;
  }

  Future<void> patch(String path, Map<String, Object?> value) async {
    final response = await http
        .patch(_uri(path), body: jsonEncode(value))
        .timeout(_timeout);
    _ensureSuccess(response);
  }

  Future<void> delete(String path) async {
    final response = await http.delete(_uri(path)).timeout(_timeout);
    _ensureSuccess(response);
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Firebase retornou ${response.statusCode}: ${response.body}');
    }
  }
}
