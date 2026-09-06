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
    // Android 上裸文件名可能找不到，依次尝试多种路径
    final candidates = [
      'libverify.so',
    ];
    // 1) 直接进程内查找（Android 7+ flutter runner 已链接时可用）
    try {
      _lib = DynamicLibrary.process();
      // 探测符号是否存在
      _lib!.lookup<NativeFunction<Void Function()>>('domain_pool');
      return _lib;
    } catch (_) {}
    // 2) 按名字加载
    for (final name in candidates) {
      try {
        _lib = DynamicLibrary.open(name);
        _lib!.lookup<NativeFunction<Void Function()>>('domain_pool');
        return _lib;
      } catch (_) {}
    }
    return null;
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
      return ['eri.kdns.fr'];
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

  /// 原生核心版本（null = SO 未加载，fallback 模式）
  String? nativeVersion() {
    try {
      final lib = _dylib;
      if (lib == null) return null;
      final fn = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('native_version');
      return _ps(fn());
    } catch (_) {
      return null;
    }
  }

  /// 更新检查 API（SO 分段构造）
  String get updateApiUrl {
    try {
      final lib = _dylib;
      if (lib == null) throw StateError('no lib');
      final fn = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('update_api_url');
      return _ps(fn());
    } catch (_) {
      return ['https://api.', 'github.', 'com/repos/Yueshen', 'yue0/tempmail/releases/tags/Can', 'ary'].join();
    }
  }

  /// 更新页兜底链接
  String get updatePageUrl {
    try {
      final lib = _dylib;
      if (lib == null) throw StateError('no lib');
      final fn = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('update_page_url');
      return _ps(fn());
    } catch (_) {
      return ['https://git', 'hub.com/Yueshen', 'yue0/tempmail/releases/tag/Can', 'ary'].join();
    }
  }

  /// 下载加速前缀
  String get updateAccelPrefix {
    try {
      final lib = _dylib;
      if (lib == null) throw StateError('no lib');
      final fn = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('update_accel_prefix');
      return _ps(fn());
    } catch (_) {
      return ['https://ghf', 'ast.top/'].join();
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