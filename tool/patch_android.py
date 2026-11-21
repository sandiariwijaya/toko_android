"""Dijalankan oleh GitHub Actions setelah `flutter create`.
- Tanda tangan APK tetap (keystore android/keystore/toko.jks) agar update bisa ditimpa tanpa uninstall
- minSdk 24 (Android 7.0) untuk kamera barcode
"""
import os, re

STORE = "../keystore/toko.jks"
PASS = "TokoApp2026"
ALIAS = "toko"

def patch_kts(p):
    s = open(p, encoding="utf-8").read()
    if 'create("release")' not in s:
        block = (
            '\n    signingConfigs {\n'
            '        create("release") {\n'
            f'            storeFile = file("{STORE}")\n'
            f'            storePassword = "{PASS}"\n'
            f'            keyAlias = "{ALIAS}"\n'
            f'            keyPassword = "{PASS}"\n'
            '        }\n'
            '    }\n'
        )
        s = s.replace("android {", "android {" + block, 1)
    s = s.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("release")')
    s = re.sub(r'minSdk\s*=\s*[^\n]+', 'minSdk = 24', s)
    open(p, "w", encoding="utf-8").write(s)

def patch_groovy(p):
    s = open(p, encoding="utf-8").read()
    if "signingConfigs {" not in s:
        block = (
            '\n    signingConfigs {\n'
            '        release {\n'
            f"            storeFile file('{STORE}')\n"
            f"            storePassword '{PASS}'\n"
            f"            keyAlias '{ALIAS}'\n"
            f"            keyPassword '{PASS}'\n"
            '        }\n'
            '    }\n'
        )
        s = s.replace("android {", "android {" + block, 1)
    s = s.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
    s = re.sub(r'minSdkVersion\s+[^\n]+', 'minSdkVersion 24', s)
    s = re.sub(r'minSdk\s*=\s*[^\n]+', 'minSdk = 24', s)
    open(p, "w", encoding="utf-8").write(s)

kts = "android/app/build.gradle.kts"
groovy = "android/app/build.gradle"
if os.path.exists(kts):
    patch_kts(kts)
    print(open(kts).read())
elif os.path.exists(groovy):
    patch_groovy(groovy)
    print(open(groovy).read())
else:
    print("build.gradle tidak ditemukan")
