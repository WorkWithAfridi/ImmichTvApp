# Release Checklist

Run this before tagging a version and publishing the build.

## Code and configuration

- [ ] `flutter analyze` reports no errors or warnings (info-level deprecations are tracked separately).
- [ ] `flutter test` passes in full.
- [ ] `flutter build apk --release` succeeds locally.
- [ ] `version:` in `pubspec.yaml` is bumped and matches `README.md`.
- [ ] `docs/RELEASE_NOTES.md` covers user-facing changes for the version.
- [ ] No debug-only profiling flag is enabled in the shipped build.

## Screenshots to capture

Capture at 1280 x 720 (TV viewport) and at a phone viewport where relevant:

- [ ] Onboarding input-method selection
- [ ] Server validation and sign-in form
- [ ] Profile picker and PIN unlock
- [ ] Timeline with year rail
- [ ] Albums browser with folder rail and date-grouped grid
- [ ] People browser
- [ ] Favorites
- [ ] Memories with year folders and date grid
- [ ] Fullscreen photo with controls
- [ ] Fullscreen video with transport controls
- [ ] Slideshow with duration controls
- [ ] Settings with PIN and playback toggles
- [ ] Offline banner during a failed refresh

## Android TV / Google TV

- [ ] Follow every step in `docs/ANDROID_TV_PACKAGING.md`.
- [ ] App appears on the TV home screen with the correct banner and name.
- [ ] Remote arrows/select/back work in every tab without trapping focus.
- [ ] On-screen keyboard completes onboarding and PIN entry.
- [ ] Video playback, HLS fallback, and slideshow work with the remote.
- [ ] Sign out and switch user work from the sidebar.
- [ ] Cold start on a flaky network shows the offline banner instead of a blank screen.

## Other platforms

- [ ] Web: app loads directly at `/`, sign-in and playback work.
- [ ] Windows, macOS, Linux: desktop builds launch and navigate with keyboard/mouse.
- [ ] Android mobile: portrait/phone layout remains usable.

## Distribution

- [ ] GitHub release has APK, checksum, metadata, and notes.
- [ ] APK checksum verified locally.
- [ ] Store listing description and topics match the repository About section.
- [ ] TV banner and screenshots uploaded.
- [ ] Staged rollout configured before public release.
