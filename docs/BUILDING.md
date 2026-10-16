# Building test builds

The export settings live in `export_presets.cfg` (Android, Windows, Linux). Debug and design files (`docs/`, `reports/`) are left out of builds.

## On your own computer (recommended)

1. Install **Godot 4.7** and, from the editor, **Editor → Manage Export Templates → Download and Install**.
2. For Android, install **Android Studio** (it brings the Android SDK) and a JDK 17+. In Godot: **Editor → Editor Settings → Export → Android**, set *Android SDK Path* and *Java SDK Path*.
3. Create your own signing key once and keep it safe (you need the same key for every update):
   `keytool -genkeypair -v -keystore crownconquest-release.keystore -alias crownconquest -keyalg RSA -keysize 3072 -validity 10000`
4. **Project → Export → Android**: tick *Signed*, point *Keystore → Release* at that file with its alias and password, then **Export Project…** and untick *Export With Debug*.
5. Windows / Linux: **Project → Export →** pick the preset → **Export Project…**.

Before each new test build, raise `version/code` (Android) by 1 and `config/version` in `project.godot`, so phones accept it as an update.

## How v0.1.0 was built (cloud machine without the Android SDK)

Google's SDK download site wasn't reachable from the build machine, so:
- Godot exported an **unsigned** APK (arm64-v8a, release) using a stand-in SDK folder that only satisfies Godot's checks;
- the APK was then signed with Android's `apksig` library (APK Signature Scheme v2, minimum Android 7) and checked with its verifier.

The test key used for v0.1.0 was handed over separately. Builds signed with a different key can't update it in place: testers would uninstall v0.1.0 first.
