# Android TV / Google TV Packaging

This document records the TV packaging setup and the checks to run before a store or sideload release.

## Manifest configuration

`android/app/src/main/AndroidManifest.xml` already contains the required TV setup:

- `android.software.leanback` is declared with `android:required="false"` so the same APK installs on phones, tablets, and TV devices.
- Touchscreen, keyboard-adjacent hardware features (camera, GPS, NFC, microphone, telephony) are all declared as `required="false"`, keeping the app out of the Play Store's "not compatible with your device" list on TV hardware.
- The launcher activity exports both `android.intent.category.LAUNCHER` and `android.intent.category.LEANBACK_LAUNCHER`, so it appears in the standard launcher and the TV home screen.
- `android:banner` points to `@drawable/tv_banner`, and `android:resizeableActivity="true"` avoids forced portrait/letterboxing on large screens.
- `android:usesCleartextTraffic="true"` is intentional: many self-hosted Immich instances are reached over plain HTTP on a local network. Users who want strict HTTPS can still configure their server accordingly.

## Phone pairing / remote validation

When phone-assisted setup or the phone remote is opened, the TV binds an ephemeral local HTTP listener and serves the bundled companion page from its own LAN address. On Android targets with local-network restrictions (API 37+), verify the runtime permission path and the in-app fallback message when it is denied. Add these steps to the device checklist above: QR scan and direct connection on a real TV, onboarding details sent from the phone, remote navigation/text/playback, connecting a second phone, session revoke from Settings, and app-background teardown.

## Banner assets

TV home screens require a 320 x 180 dp banner. The following densities are bundled and must stay at these exact sizes:

| Density | File | Size |
|---|---|---|
| mdpi | `res/drawable-mdpi/tv_banner.png` | 320 x 180 |
| hdpi | `res/drawable-hdpi/tv_banner.png` | 480 x 270 |
| xhdpi | `res/drawable-xhdpi/tv_banner.png` | 640 x 360 |
| xxhdpi | `res/drawable-xxhdpi/tv_banner.png` | 960 x 540 |
| xxxhdpi | `res/drawable-xxxhdpi/tv_banner.png` | 1280 x 720 |

## Building

```bash
flutter clean
flutter pub get
flutter build apk --release          # sideload / direct install
flutter build appbundle --release    # Play Store upload
```

Signing credentials are read from `android/key.properties` when present. The file is not committed; without it Gradle falls back to debug signing so fresh checkouts and CI can still build. See `android/signing/` for the keystore layout used by releases.

## Device checklist

Before shipping, install the release build on a real Android TV / Google TV device and verify:

1. The app appears on the TV home screen with the correct banner and name.
2. Launching with the remote opens directly into onboarding or the saved-profile picker.
3. Remote arrows, select, and back navigate every tab without trapping focus.
4. The on-screen keyboard can complete onboarding and PIN entry using only the remote.
5. Fullscreen photos, video playback, and slideshow work with the remote.
6. Signing out and switching users work from the sidebar.
7. A cold start on a constrained network still reaches the profile picker and shows the offline banner when a refresh fails.

Useful commands:

```bash
adb devices
adb install build/app/outputs/flutter-apk/app-release.apk
adb logcat | grep -i immich
```

## Store metadata

- Target Android TV / Google TV as a device type in the Play Console.
- Upload the 320 x 180 banner plus feature graphics required by the TV program.
- Keep the application ID `com.workwithafridi.immichtv` stable; changing it creates a separate listing and loses saved profiles.
- The app is read-only with respect to the Immich library; no photo library or storage permission is requested.
