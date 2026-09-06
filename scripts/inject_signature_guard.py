#!/usr/bin/env python3
"""注入 MainActivity.kt：只负责取签名字节并通过 JNI 传给 SO 校验。
指纹不在 dex 里（在 SO 中 XOR 混淆），dex 层无任何可改的校验逻辑。
"""
import os

ACTIVITY_DIR = 'android/app/src/main/kotlin/com/eri/tempmail'


def main():
    os.makedirs(ACTIVITY_DIR, exist_ok=True)
    path = os.path.join(ACTIVITY_DIR, 'MainActivity.kt')
    if os.path.exists(path):
        src = open(path, encoding='utf-8').read()
        if 'nativeSigMatch' in src:
            print('already injected')
            return

    code = '''package com.eri.tempmail

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        init {
            System.loadLibrary("verify")
        }
    }

    // SO 层校验：返回 1=匹配 0=不匹配（指纹在 SO 内部，dex 无感知）
    external fun sigMatch(sigBytes: ByteArray): Int

    fun isOfficialSignature(): Boolean {
        return try {
            val pm = applicationContext.packageManager
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                    .signingInfo?.apkContentsSigners
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures
            }
            val sig = signatures?.firstOrNull() ?: return false
            sigMatch(sig.toByteArray()) == 1
        } catch (t: Throwable) {
            false
        }
    }
}
'''
    open(path, 'w', encoding='utf-8').write(code)
    print('MainActivity (JNI bridge) injected')


if __name__ == '__main__':
    main()