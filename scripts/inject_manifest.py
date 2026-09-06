#!/usr/bin/env python3
"""manifest 注入：权限 + 自有 FileProvider（应用内更新安装用）"""
import os

def main():
    f = 'android/app/src/main/AndroidManifest.xml'
    s = open(f, encoding='utf-8').read()

    # 1. 权限 + queries
    if 'REQUEST_INSTALL_PACKAGES' not in s:
        s = s.replace(
            '<application',
            '<uses-permission android:name="android.permission.INTERNET"/>'
            '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>'
            '<queries><intent><action android:name="android.intent.action.VIEW"/>'
            '<data android:scheme="https"/></intent></queries><application',
            1)
        print('permissions injected')

    # 2. label
    s = s.replace('android:label="tempmail"', 'android:label="TempMail"')

    # 3. 自有 FileProvider
    if 'androidx.core.content.FileProvider' not in s:
        provider = (
            '    <provider\n'
            '        android:name="androidx.core.content.FileProvider"\n'
            '        android:authorities="${applicationId}.fileprovider"\n'
            '        android:exported="false"\n'
            '        android:grantUriPermissions="true">\n'
            '        <meta-data\n'
            '            android:name="android.support.FILE_PROVIDER_PATHS"\n'
            '            android:resource="@xml/filepaths" />\n'
            '    </provider>\n'
        )
        s = s.replace('</application>', provider + '    </application>', 1)
        print('own FileProvider registered')

    open(f, 'w', encoding='utf-8').write(s)
    print('manifest done')

if __name__ == '__main__':
    main()