import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_bridge.dart';

/// Canary 应用内更新：
/// 1. SO 取检查端点（无明文地址）
/// 2. 新版本 -> 强制弹窗（不可关闭）
/// 3. 点更新 -> 应用内下载（进度条）-> 自动触发安装
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  String? _apkUrl;
  String? _publishedAt;
  bool _downloading = false;
  StateCallback? _uiCallback;

  /// UI 状态回调（由弹窗注册）
  static void Function(OtaEvent event)? onOtaEvent;
  static void Function(String error)? onOtaError;

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
      builder: (ctx) => const UpdateDialog(),
    );
  }

  Future<void> _startInAppUpdate() async {
    if (_downloading || _apkUrl == null) return;
    _downloading = true;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('tm_seen_canary', _publishedAt ?? '');
    // ghfast 加速直链
    final url = '${NativeCore.instance.updateAccelPrefix}$_apkUrl';
    try {
      OtaUpdate()
          .execute(url, destinationFilename: 'tempmail_canary.apk')
          .listen(
        (OtaEvent event) {
          onOtaEvent?.call(event);
        },
        onError: (e) {
          _downloading = false;
          onOtaError?.call(e.toString());
        },
        onDone: () => _downloading = false,
      );
    } catch (e) {
      _downloading = false;
      onOtaError?.call(e.toString());
    }
  }

  static void startUpdate() => instance._startInAppUpdate();
}

typedef StateCallback = void Function();

/// 更新弹窗 UI：进度条 + 状态展示
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  double _progress = 0;
  String _statusText = '检测到新的 Canary 版本，必须更新后才能使用';
  bool _downloading = false;
  bool _failed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    UpdateService.onOtaEvent = (event) {
      if (!mounted) return;
      setState(() {
        final status = event.status.toString();
        final value = event.value?.toString();
        if (status.contains('DOWNLOADING')) {
          _downloading = true;
          _progress = double.tryParse(value ?? '0') ?? 0;
          _statusText = '下载中 ${_progress.toStringAsFixed(0)}%';
        } else if (status.contains('INSTALLING')) {
          _downloading = true;
          _progress = 100;
          _statusText = '下载完成，正在启动安装...';
        } else if (status.contains('INSTALLATION_DONE')) {
          _statusText = '安装完成';
        } else if (status.contains('ERROR')) {
          _failed = true;
          _error = value ?? status;
          _statusText = '出错';
        }
      });
    };
    UpdateService.onOtaError = (msg) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _error = msg;
        _statusText = '出错';
      });
    };
  }

  @override
  void dispose() {
    UpdateService.onOtaEvent = null;
    UpdateService.onOtaError = null;
    super.dispose();
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
            if (_failed) ...[
              const SizedBox(height: 12),
              Text(_error ?? '下载失败',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
        actions: [
          if (!_downloading && !_failed)
            FilledButton(
              onPressed: UpdateService.startUpdate,
              child: const Text('立即更新'),
            ),
          if (_failed)
            TextButton(
              onPressed: () => exit(0),
              child: const Text('退出应用'),
            ),
        ],
      ),
    );
  }
}