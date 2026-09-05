import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// SO 原生桥：端点构造 + 域名池 + token 解混淆
/// 核心逻辑在 verify.cpp 里实现，Dart 侧只有函数签名
class NativeCore {
  NativeCore._();
  static NativeCore? _instance;
  static NativeCore get instance => _instance ??= NativeCore._();

  DynamicLibrary? _lib;
  DynamicLibrary? get _dylib {
    if (_lib != null) return _lib;
    try {
      _lib = DynamicLibrary.open('libverify.so');
    } catch (_) {
      return null;
    }
    return _lib;
  }

  // C 函数签名
  late final _apiUrl = _dylib!
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>('api_url');
  late final _domains = _dylib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'domain_pool');
  late final _unmask = _dylib!
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('unmask_token');
  late final _embeddedToken = _dylib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'embedded_token');

  String _ps(Pointer<Utf8> p) => p.toDartString();

  String apiUrl(String path, String query) {
    try {
      return _ps(_apiUrl(path.toNativeUtf8(), query.toNativeUtf8()));
    } catch (_) {
      return 'https://api.mail.cx/v1$path$query';
    }
  }

  /// 从 SO 里的域名池取一个域名
  List<String> domainPool() {
    try {
      final raw = _ps(_domains());
      return raw.split(',').where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return ['uqu.me', 'ddker.com', '9k3r.com'];
    }
  }

  /// 解混淆 token（SO 内嵌 XOR 表）
  String unmaskToken(String masked) {
    try {
      return _ps(_unmask(masked.toNativeUtf8()));
    } catch (_) {
      return masked;
    }
  }

  /// SO 内嵌 token（无需用户配置）
  String? embeddedToken() {
    try {
      final t = _ps(_embeddedToken());
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  /// 随机 local part（SO 里生成）
  String randLocal() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = DateTime.now().microsecondsSinceEpoch;
    final buf = StringBuffer();
    var x = rnd;
    for (var i = 0; i < 10; i++) {
      x = (x * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF;
      buf.write(chars[(x >> 33) % chars.length]);
    }
    return buf.toString();
  }
}