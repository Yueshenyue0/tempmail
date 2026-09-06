import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_bridge.dart';

/// Canary 应用内更新：
/// 1. SO 取检查端点（Dart 快照无明文地址）
/// 2. 新版本 -> 强制弹窗（不可关闭）
/// 3. 点更新 -> 应用内下载（进度条）-> 自动触发系统安装
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  String? _apkUrl;
  String? _publishedAt;
  bool _downloading = false;

  /// 启动检查。返回 true 表示弹了强制更新框。
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
      final req =
          await client.getUrl(Uri.parse(NativeCore.instance.updateApiUrl));
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

  Future<void> _showForceDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDialog(controller: this),
    );
  }

  /// 开始应用内下载（由弹窗按钮触发）
  Future<void> startDownload(void Function(OtaEvent) onEvent,
      void Function(String) onError) async {
    if (_downloading || _apkUrl == null) return;
    _downloading = true;
    // 标记已见，装完新版启动不再弹
    final sp = await SharedPreferences.getInstance();
    await sp.setString('tm_seen_canary', _publishedAt ?? '');
    // ghfast 加速直链
    final url = '${NativeCore.instance.updateAccelPrefix}$_apkUrl';
    try {
      OtaUpdate().execute(
        url,
        destinationFilename: 'tempmail_canary.apk',
      ).listen(
        (OtaEvent event) => onEvent(event),
        onError: (e) {
          _downloading = false;
          onError(e.toString());
        },
        onDone: () => _downloading = false,
        cancelOnError: true,
      );
    } catch (e) {
      _downloading = false;
      onError(e.toString());
    }
  }
}

// ==================== 更新弹窗 UI（进度条） ====================

class _UpdateDialog extends StatefulWidget {
  final UpdateService controller;
  const _UpdateDialog({required this.controller});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0;
  String _statusText = '检测到新的 Canary 版本，必须更新后才能继续使用';
  bool _downloading = false;
  bool _failed = false;

  void _onEvent(OtaEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.status) {
        case OtaStatus.DOWNLOADING:
          _downloading = true;
          _progress =
              double.tryParse(event.value ?? '0') ?? 0;
          _statusText = '下载中 ${_progress.toStringAsFixed(0)}%';
          break;
        case OtaStatus.INSTALLING:
          _downloading = true;
          _progress = 100;
          _statusText = '下载完成，正在启动安装...';
          break;
        case OtaStatus.ALREADY_RUNNING_ERROR:
          break;
        case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
          _failed = true;
          _statusText = '未授予安装权限';
          break;
        case OtaStatus.DOWNLOAD_ERROR:
          _failed = true;
          _statusText = '下载失败，请检查网络';
          break;
        case OtaStatus.INTERNAL_ERROR:
          _failed = true;
          _statusText = '出错: ${event.value ?? ''}';
          break;
        default:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('发现新版本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_statusText, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (_downloading || _progress > 0)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 10,
                ),
              ),
          ],
        ),
        actions: [
          if (_failed)
            TextButton(
              onPressed: () => exit(0),
              child: const Text('退出应用'),
            ),
          if (!_downloading && !_failed)
            FilledButton(
              onPressed: () => widget.controller
                  .startDownload(_onEvent, (msg) {
                if (mounted) {
                  setState(() {
                    _failed = true;
                    _statusText = '出错: $msg';
                  });
                }
              }),
              child: const Text('立即更新'),
            ),
        ],
      ),
    );
  }
}