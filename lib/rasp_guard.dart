import 'package:flutter/foundation.dart';
import 'package:flutter_rasp/flutter_rasp.dart';

/// RASP 防护：root / hook / 重打包 自动退出
/// VPN / 调试器 / 模拟器 只上报不强杀（避免误报误杀）
class RaspGuard {
  RaspGuard._();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      await FlutterRasp.instance.initialize(
        config: const RaspConfig(
          // 自定义策略：只强杀这三类。VPN 等只在 detectedThreats 里上报
          policy: ThreatPolicy(exitThreats: {
            Threat.root,
            Threat.hook,
            Threat.repackaging,
          }),
          monitoringInterval: Duration(seconds: 15),
          androidConfig: AndroidRaspConfig(
            // 官方签名证书 SHA-256，重打包检测依赖它
            signingCertHashes: [
              'B2:50:00:D1:0B:0C:1D:A5:C7:D7:28:C0:6C:99:22:BE:83:4C:D3:29:41:63:C3:20:55:2F:24:82:5A:9B:AB:51',
            ],
          ),
        ),
        onThreatDetected: (threats) {
          // 上报型威胁只打日志，不退出
          debugPrint('[RASP] detected: $threats');
        },
      );
      _initialized = true;
    } catch (e) {
      debugPrint('[RASP] init failed: $e');
    }
  }

  /// 一次性全量扫描（可用于设置页"安全状态"显示）
  static Future<Set<Threat>> scanAll() async {
    try {
      final result = await FlutterRasp.instance.scanAll();
      return result.detectedThreats;
    } catch (_) {
      return <Threat>{};
    }
  }
}