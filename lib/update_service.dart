import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'native_bridge.dart';

/// Canary 更新检测：比对 release 的 updated_at 与本地记录，
/// 出现新的 Canary 包即弹强制更新（只能点"立即更新"）。
/// 端点由 SO 构造，Dart 快照中无完整明文地址。
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  String? _apkUrl;
  String? _publishedAt;

  /// 启动检查。返回 true 表示弹了强制更新框（调用方此后不要继续引导用户）。
  Future<bool> checkAndPrompt(BuildContext context) async {
    try {
      final data = await _fetchRelease();
      if (data == null) return false;
      final assets = data['assets'] as List? ?? [];
      final apk = assets.firstWhere(
        (a) => (a['name'] as String? ?? '').endsWith('.apk'),
        orElse: () => null,
      );
      if (apk == null) return false;
      _apkUrl = apk['browser_download_url'] as String?;
      _publishedAt = data['published_at'] as String? ??
          data['created_at'] as String? ??
          '';

      final sp = await SharedPreferences.getInstance();
      final seen = sp.getString('tm_seen_canary');
      if (seen == _publishedAt) return false;
      if (!context.mounted) return false;
      await _showForceDialog(context);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _fetchRelease() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12);
      final req = await client.getUrl(Uri.parse(NativeCore.instance.updateApiUrl));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'tempmail-app');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 浏览器直链换加速前缀下载
  String get _acceleratedUrl {
    final raw = _apkUrl ?? '';
    if (raw.isEmpty) return NativeCore.instance.updatePageUrl;
    return '${NativeCore.instance.updateAccelPrefix}$raw';
  }

  Future<void> _showForceDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('发现新版本'),
          content: const Text(
              '检测到新的 Canary 版本。\n本版本为强制更新，请先更新再使用。'),
          actions: [
            FilledButton(
              onPressed: () => _openDownload(),
              child: const Text('立即更新'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDownload() async {
    // 记住这个版本，装完新版启动就不会再弹
    final sp = await SharedPreferences.getInstance();
    await sp.setString('tm_seen_canary', _publishedAt ?? '');
    final uri = Uri.parse(_acceleratedUrl);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(Uri.parse(NativeCore.instance.updatePageUrl),
            mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(Uri.parse(NativeCore.instance.updatePageUrl),
            mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }
}