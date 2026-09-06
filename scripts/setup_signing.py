#!/usr/bin/env python3
"""向 android/app/build.gradle(.kts) 注入固定签名配置
幂等：已注入则跳过。kts/groovy 双兼容。
"""
import os
import sys

KTS = 'android/app/build.gradle.kts'
GROOVY = 'android/app/build.gradle'


def main():
    if os.path.exists(KTS):
        f, is_kts = KTS, True
    elif os.path.exists(GROOVY):
        f, is_kts = GROOVY, False
    else:
        sys.exit('no build.gradle(.kts) found')

    s = open(f, encoding='utf-8').read()

    if 'key.properties' in s:
        print('signing already configured')
        return

    if is_kts:
        header = (
            'import java.util.Properties\n'
            'import java.io.FileInputStream\n'
            '\n'
            'val keystoreProps = java.util.Properties().apply {\n'
            '    val pf = rootProject.file("key.properties")\n'
            '    if (pf.exists()) java.io.FileInputStream(pf).use { load(it) }\n'
            '}\n'
            '\n'
        )
        sign_block = (
            '    signingConfigs {\n'
            '        create("release") {\n'
            '            storeFile = file(keystoreProps.getProperty("storeFile"))\n'
            '            storePassword = keystoreProps.getProperty("storePassword")\n'
            '            keyAlias = keystoreProps.getProperty("keyAlias")\n'
            '            keyPassword = keystoreProps.getProperty("keyPassword")\n'
            '        }\n'
            '    }\n'
        )
        rel_line = '            signingConfig = signingConfigs.getByName("release")\n'
        # buildTypes 里插入/修正 release 块的签名
        if 'signingConfig = signingConfigs.getByName("debug")' in s:
            # Flutter 模板默认 debug 签名 → 替换为 release 签名
            s = s.replace(
                'signingConfig = signingConfigs.getByName("debug")',
                'signingConfig = signingConfigs.getByName("release")')
        else:
            s2 = s.replace('    buildTypes {\n',
                           '    buildTypes {\n        release {\n' + rel_line + '        }\n', 1)
            if s2 == s and 'release {' in s.split('buildTypes {')[1][:200]:
                s2 = s.replace('        release {\n', '        release {\n' + rel_line, 1)
            s = s2
        s = header + s
        s = s.replace('    android {\n', '    android {\n' + sign_block, 1)
        if sign_block not in s:
            s = s.replace('android {\n', 'android {\n' + sign_block, 1)
    else:
        header = ''
        sign_block = (
            '    signingConfigs {\n'
            '        release {\n'
            "            storeFile file(keystoreProps['storeFile'])\n"
            "            storePassword keystoreProps['storePassword']\n"
            "            keyAlias keystoreProps['keyAlias']\n"
            "            keyPassword keystoreProps['keyPassword']\n"
            '        }\n'
            '    }\n'
        )
        s = ("def keystoreProps = new Properties()\n"
             "def keystoreFile = rootProject.file('key.properties')\n"
             "if (keystoreFile.exists()) keystoreFile.withInputStream { keystoreProps.load(it) }\n"
             '\n') + s
        s = s.replace('android {\n', 'android {\n' + sign_block, 1)
        s = s.replace('    buildTypes {\n',
                      '    buildTypes {\n        release {\n'
                      '            signingConfig signingConfigs.release\n'
                      '        }\n', 1)

    open(f, 'w', encoding='utf-8').write(s)
    print('signing injected into', f)


if __name__ == '__main__':
    main()