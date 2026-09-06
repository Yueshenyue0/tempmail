#!/usr/bin/env python3
"""注入 MainActivity.kt：
1. 提供 MethodChannel 'sig_guard/getSignature' 返回 APK 签名字节
2. 签名校验本体在 SO（sig_match JNI），Kotlin 只搬运字节，无指纹明文
幂等。
"""
import os

ACTIVITY_DIR = 'android/app/src/main/kotlin/com/eri/tempmail'

CODE = '''// SIGNATURE_BRIDGE: Kotlin 只负责取签名字节，校验逻辑在 libverify.so
package com.eri.tempmail

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "sig_guard"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSignature" -> {
                        try {
                            val pm = applicationContext.packageManager
                            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                                    .signingInfo?.apkContentsSigners
                            } else {
                                @Suppress("DEPRECATION")
                                pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures
                            }
                            if (signatures != null && signatures.isNotEmpty()) {
                                result.success(signatures[0].toByteArray())
                            } else {
                                result.error("NO_SIG", "no signature", null)
                            }
                        } catch (t: Throwable) {
                            result.error("ERR", t.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
'''


def main():
    os.makedirs(ACTIVITY_DIR, exist_ok=True)
    path = os.path.join(ACTIVITY_DIR, 'MainActivity.kt')
    open(path, 'w', encoding='utf-8').write(CODE)
    print('MainActivity signature bridge injected')


if __name__ == '__main__':
    main()