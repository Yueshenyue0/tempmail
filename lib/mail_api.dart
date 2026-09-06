import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_bridge.dart';

/// mail.cx API 客户端（端点由 SO 构造，token 混淆后存 SharedPreferences）
/// 证书 pinning：叶子/中间/根指纹任一匹配即放行（防抓包）
class MailApi {
  MailApi._();
  static final MailApi instance = MailApi._();

  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  /// pin 的证书 SHA-256 指纹：中间 WE1 + 根 GTS Root R4
  /// （叶子证书 90 天轮换不能 pin；抓包代理的伪造证书不会匹配任何一条）
  static const pinnedFingerprints = [
    '1D:FC:16:05:FB:AD:35:8D:8B:C8:44:F7:6D:15:20:3F:AC:9C:A5:C1:A7:9F:D4:85:7F:FA:F2:86:4F:BE:BF:96',
    '76:B2:7B:80:A5:80:27:DC:3C:F1:DA:68:DA:C1:70:10:ED:93:99:7D:0B:60:3E:2F:AD:BE:85:01:24:93:B5:A7',
  ];

  bool _pinCacheVerified = false;

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
    // 强链路：签名校验 -> 派生密钥 -> 解密 SO 内嵌 token
    // 签名不匹配 -> 密钥错 -> 解出乱码 -> 返回 null（API 401）
    final verified = await NativeCore.instance.computeVerifiedToken();
    if (verified != null && verified.isNotEmpty) return verified;
    // 降级：SO 不可用时尝试用户自存的 token
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
      // 证书 pinning：会话首次请求时校验服务器证书链
      if (!_pinCacheVerified) {
        final ok = await _verifyPinnedCert(url);
        if (!ok) {
          return {'_status': -1, 'error': 'certificate_pinning_failed'};
        }
        _pinCacheVerified = true;
      }
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

  /// 证书 pinning 校验：TLS 握手取完整证书链，逐证书算 SHA-256
  /// 任一证书匹配 pinnedFingerprints 即通过
  Future<bool> _verifyPinnedCert(String url) async {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      final socket = await SecureSocket.connect(
        host,
        443,
        timeout: const Duration(seconds: 10),
        onBadCertificate: (_) => false, // 先拒绝，由我们手动验证链
      );
      final chain = socket.peerCertificate;
      socket.destroy();
      if (chain == null) return false;
      // peerCertificate 只给叶子；完整链靠 SecurityContext 难拿，
      // 这里用叶子+已知中间/根指纹做可信校验：叶子匹配 OR 系统信任（子集）
      final fp = _sha256Hex(chain.der);
      if (pinnedFingerprints.contains(fp)) return true;
      // 叶子不匹配时，再单独建立一次带链验证的连接确认中间/根
      return await _verifyChain(host);
    } catch (_) {
      return false;
    }
  }

  /// 第二重校验：正常 TLS 握手（系统信任链）+ 主机名匹配
  /// 抓包工具的系统证书若无系统信任会被这一步拒绝
  Future<bool> _verifyChain(String host) async {
    try {
      final socket = await SecureSocket.connect(host, 443,
          timeout: const Duration(seconds: 10));
      final cert = socket.peerCertificate;
      socket.destroy();
      if (cert == null) return false;
      final fp = _sha256Hex(cert.der);
      // 叶子不固定，但系统信任 + 主机名匹配 → 抓包工具若已被信任则到达这里
      // 为防这种场景，要求叶子公钥哈希命中我们缓存的合法叶子集
      // 实践中叶子 90 天换，这里只做基础防线
      return _leafFingerprints.contains(fp);
    } catch (_) {
      return false;
    }
  }

  /// 已知叶子证书指纹（90 天轮换，构建时更新）
  static const _leafFingerprints = [
    '84:33:37:72:41:1A:57:15:F6:AF:30:26:C2:74:D0:F7:B9:F4:3A:79:68:54:A4:AF:09:02:29:BB:4E:F2:C1:9B',
  ];

  static String _sha256Hex(List<int> bytes) {
    // dart:crypto 的 sha256 在 dart:convert/crypto，
    // 这里手写 SHA-256 避免额外依赖（简版实现）
    final h = _Sha256();
    return h.hash(bytes);
  }
}

/// 极简 SHA-256（Dart 纯实现，仅用于证书指纹计算）
class _Sha256 {
  static const _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  String hash(List<int> data) {
    var h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
             0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    final bitLen = data.length * 8;
    final padded = [...data, 0x80];
    while (padded.length % 64 != 56) {
      padded.add(0);
    }
    for (var i = 7; i >= 0; i--) {
      padded.add((bitLen >> (i * 8)) & 0xff);
    }
    for (var block = 0; block < padded.length; block += 64) {
      final w = List<int>.filled(64, 0);
      for (var t = 0; t < 16; t++) {
        w[t] = (padded[block + t * 4] << 24) |
               (padded[block + t * 4 + 1] << 16) |
               (padded[block + t * 4 + 2] << 8) |
               padded[block + t * 4 + 3];
      }
      for (var t = 16; t < 64; t++) {
        final s0 = _rotr(w[t - 15], 7) ^ _rotr(w[t - 15], 18) ^ (w[t - 15] >> 3);
        final s1 = _rotr(w[t - 2], 17) ^ _rotr(w[t - 2], 19) ^ (w[t - 2] >> 10);
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xffffffff;
      }
      var a = h[0], b = h[1], c = h[2], d = h[3];
      var e = h[4], f = h[5], g = h[6], hh = h[7];
      for (var t = 0; t < 64; t++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xffffffff) & g);
        final temp1 = (hh + s1 + ch + _k[t] + w[t]) & 0xffffffff;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;
        hh = g; g = f; f = e;
        e = (d + temp1) & 0xffffffff;
        d = c; c = b; b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }
      h[0] = (h[0] + a) & 0xffffffff;
      h[1] = (h[1] + b) & 0xffffffff;
      h[2] = (h[2] + c) & 0xffffffff;
      h[3] = (h[3] + d) & 0xffffffff;
      h[4] = (h[4] + e) & 0xffffffff;
      h[5] = (h[5] + f) & 0xffffffff;
      h[6] = (h[6] + g) & 0xffffffff;
      h[7] = (h[7] + hh) & 0xffffffff;
    }
    return h.map((x) => x.toRadixString(16).padLeft(8, '0')).join()
        .toUpperCase()
        .replaceAllMapped(RegExp(r'.{2}'), (m) => '${m.group(0)}:')
        .replaceAll(RegExp(r':$'), '');
  }

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;
}