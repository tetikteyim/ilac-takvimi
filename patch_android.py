#!/usr/bin/env python3
"""flutter create sonrasi Android projesini yamalar:
- Bildirim / kesin alarm izinleri
- flutter_local_notifications alicilari (receiver)
- Java 8+ desugaring (kutuphane geregi)
- Yatay ekran kilidi ve uygulama adi
"""
import io, re, sys

MANIFEST = "android/app/src/main/AndroidManifest.xml"
GRADLE = "android/app/build.gradle"

PERMISSIONS = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
"""

RECEIVERS = """        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""


def patch_manifest():
    with io.open(MANIFEST, encoding="utf-8") as f:
        s = f.read()
    if "POST_NOTIFICATIONS" not in s:
        s = s.replace("<application", PERMISSIONS + "    <application", 1)
    if "ScheduledNotificationReceiver" not in s:
        s = s.replace("</application>", RECEIVERS + "    </application>", 1)
    # Uygulama adi
    s = re.sub(r'android:label="[^"]*"', 'android:label="İlaç Takvimi"', s, count=1)
    # Yatay + dikey serbest: onceki surumlerdeki kilidi kaldir.
    s = re.sub(r'\n\s*android:screenOrientation="[^"]*"', '', s)
    with io.open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(s)
    print("Manifest yamalandi.")


def patch_gradle():
    with io.open(GRADLE, encoding="utf-8") as f:
        s = f.read()
    if "coreLibraryDesugaringEnabled" not in s:
        s = s.replace(
            "compileOptions {",
            "compileOptions {\n        coreLibraryDesugaringEnabled true",
            1,
        )
    if "desugar_jdk_libs" not in s:
        s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'\n}\n"
    with io.open(GRADLE, "w", encoding="utf-8") as f:
        f.write(s)
    print("build.gradle yamalandi.")


if __name__ == "__main__":
    try:
        patch_manifest()
        patch_gradle()
    except FileNotFoundError as e:
        print("Once 'flutter create .' calistirin:", e)
        sys.exit(1)
