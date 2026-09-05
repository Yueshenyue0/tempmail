import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_bridge.dart';

/// mail.cx API 客户端（端点由 SO 构造，token 混淆后存 SharedPreferences）
class MailApi {
  MailApi._();
  static final MailApi instance = MailApi._();

  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  // 与 SO 内 KEY 一致
  static const _maskKey = [0x5A, 0x3C, 0x7E, 0x91, 0x24, 0xB8, 0x6D, 0xF0];

  static String _mask(String s) {
    final bytes = utf8.encode(s);
    final out = List<int>.generate(
        bytes.length, (i) => bytes[i] ^ _maskKey[i % _maskKey.length]);
    return base64.encode(out);
  }

  static String _unmask(String b64) {
    try {
      final bytes = base64.decode(b64);
      final out = List<int>.generate(
          bytes.length, (i) => bytes[i] ^ _maskKey[i % _maskKey.length]);
      return utf8.decode(out);
    } catch (_) {
      return b64;
    }
  }

  String apiUrl(String path, {String query = ''}) =>
      NativeCore.instance.apiUrl(path, query);

  String get domainPool => NativeCore.instance.domainPool().join(',');

  Future<String?> loadToken() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final masked = sp.getString('tm_token_masked');
      if (masked == null || masked.isEmpty) return null;
      return _unmask(masked);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveToken(String token) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('tm_token_masked', _mask(token));
  }

  Future<void> clearToken() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('tm_token_masked');
    await sp.remove('tm_current_addr');
  }

  Future<String?> loadAddress() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString('tm_current_addr');
  }

  Future<void> saveAddress(String addr) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('tm_current_addr', addr);
  }

  Future<Map<String, dynamic>> _req(String method, String url,
      {String? token, Object? body, Duration timeout = const Duration(seconds: 30)}) async {
    try {
      final req = await _client.openUrl(method, Uri.parse(url));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null && token.isNotEmpty) {
        req.headers.set('x-api-token', token);
      }
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final resp = await req.close().timeout(timeout);
      final text = await resp.transform(utf8.decoder).join();
      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(text);
        data = decoded is Map<String, dynamic> ? decoded : {'data': decoded};
      } catch (_) {
        data = {'_raw': text};
      }
      data['_status'] = resp.statusCode;
      return data;
    } catch (e) {
      return {'_status': 0, 'error': e.toString()};
    }
  }

  /// 等收件箱新邮件（long-poll，服务端最多 25s）
  Future<Map<String, dynamic>> waitInbox(String addr,
      {String? since, int count = 1, String? token}) {
    final q = StringBuffer();
    if (since != null && since.isNotEmpty) q.write('?since=${Uri.encodeComponent(since)}');
    if (count != 1) {
      q.write(q.isEmpty ? '?' : '&');
      q.write('count=$count');
    }
    return _req('GET', apiUrl('/inbox/$addr', query: q.toString()), token: token,
        timeout: const Duration(seconds: 40));
  }

  /// 域名级监听
  Future<Map<String, dynamic>> waitDomain(String domain,
      {String? since, int count = 1, String? token}) {
    final q = StringBuffer();
    if (since != null && since.isNotEmpty) q.write('?since=${Uri.encodeComponent(since)}');
    if (count != 1) {
      q.write(q.isEmpty ? '?' : '&');
      q.write('count=$count');
    }
    return _req('GET', apiUrl('/domain/$domain', query: q.toString()), token: token,
        timeout: const Duration(seconds: 40));
  }

  /// 全部自有地址
  Future<Map<String, dynamic>> waitMe({String? since, int count = 1, String? token}) {
    final q = StringBuffer();
    if (since != null && since.isNotEmpty) q.write('?since=${Uri.encodeComponent(since)}');
    if (count != 1) {
      q.write(q.isEmpty ? '?' : '&');
      q.write('count=$count');
    }
    return _req('GET', apiUrl('/me', query: q.toString()), token: token,
        timeout: const Duration(seconds: 40));
  }

  Future<Map<String, dynamic>> emailDetail(String id, {String? token}) =>
      _req('GET', apiUrl('/email/$id'), token: token);

  Future<Map<String, dynamic>> deleteEmail(String id, {String? token}) =>
      _req('DELETE', apiUrl('/email/$id'), token: token);

  Future<Map<String, dynamic>> clearInbox(String addr, {String? token}) =>
      _req('DELETE', apiUrl('/inbox/$addr'), token: token);

  Future<Map<String, dynamic>> serverConfig() =>
      _req('GET', apiUrl('/config'));

  Future<Map<String, dynamic>> listDomains({String? token}) =>
      _req('GET', apiUrl('/domains'), token: token);

  /// 下载附件
  Future<List<int>?> downloadAttachment(String emailId, int index,
      {String? token}) async {
    try {
      final req = await _client.openUrl(
          'GET', Uri.parse(apiUrl('/email/$emailId/attachments/$index')));
      if (token != null && token.isNotEmpty) {
        req.headers.set('x-api-token', token);
      }
      final resp = await req.close().timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) return null;
      final builder = BytesBuilder();
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } catch (_) {
      return null;
    }
  }
}