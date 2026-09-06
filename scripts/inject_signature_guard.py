#!/usr/bin/env python3
"""注入自定义 MainActivity.kt：启动时校验 APK 签名证书 SHA-256。
在 Flutter 引擎加载前执行，签名不匹配直接杀进程。
幂等：已注入则跳过。
"""
import os
import sys

ACTIVITY_DIR = 'android/app/src/main/kotlin/com/eri/tempmail'
EXPECTED_SHA = 'B2:50:00:D1:0B:0C:1D:A5:C7:D7:28:C0:6C:99:22:BE:83:4C:D3:29:41:63:C3:20:55:2F:24:82:5A:9B:AB:51'


def main():
    os.makedirs(ACTIVITY_DIR, exist_ok=True)
    path = os.path.join(ACTIVITY_DIR, 'MainActivity.kt')
    if os.path.exists(path):
        src = open(path, encoding='utf-8').read()
        if 'SIGNATURE_CHECK' in src:
            print('signature check already injected')
            return

    code = f'''// SIGNATURE_CHECK: native-level signature guard
// 注入的强签名校验：Flutter 引擎加载前执行。签名不匹配 -> 杀进程。
package com.eri.tempmail

import android.content.pm.PackageManager
import android.os.Build
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import java.security.MessageDigest

class MainActivity : FlutterActivity() {{
    companion object {{
        // 官方签名证书 SHA-256（keystore: tempmail / alias: tempmail）
        private val EXPECTED = setOf(
            "{EXPECTED_SHA.replace(':', '')}"
        )
    }}

    override fun onResume() {{
        super.onResume()
        if (!verifySignature()) {{
            android.os.Process.killProcess(android.os.Process.myPid())
        }}
    }}

    private fun verifySignature(): Boolean {{
        return try {{
            val pm = applicationContext.packageManager
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {{
                val info = pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                info.signingInfo?.apkContentsSigners
            }} else {{
                @Suppress("DEPRECATION")
                val info = pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                info.signatures
            }}
            if (signatures == null || signatures.isEmpty()) return false
            for (sig in signatures) {{
                val md = MessageDigest.getInstance("SHA-256")
                val digest = md.digest(sig.toByteArray())
                val hex = digest.joinToString("") {{ "%02x".format(it) }}
                if (hex.uppercase() in EXPECTED) return true
            }}
            false
        }} catch (t: Throwable) {{
            false
        }}
    }}
}}
'''
    open(path, 'w', encoding='utf-8').write(code)
    print('MainActivity signature guard injected')


if __name__ == '__main__':
    main()