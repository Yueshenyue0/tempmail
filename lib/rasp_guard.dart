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