# Releasing Immich TV

Release automation lives in `.github/workflows/build-release-apk.yml`. It builds a signed-or-debug-compatible release APK, generates release notes and a SHA256 checksum, and publishes a GitHub release.

## Versioning

The single source of truth is `version:` in `pubspec.yaml` (`<major>.<minor>.<patch>+<build>`).

- Bump the version in a dedicated commit before you want a release produced.
- Keep `README.md` → Current Version in sync.
- Update `docs/RELEASE_NOTES.md` with user-facing highlights for the version.

When a push to `master` changes the version, CI creates the matching `v<version>` tag automatically and publishes a versioned release. Pushes that do **not** change the version update the rolling `master-latest` release instead. Pushing a `v*` tag manually also produces a versioned release, and CI validates that the tag matches `pubspec.yaml`.

## Release assets

Each GitHub release contains:

- `ImmichTV.v<version>-<build>.apk` — installable Android TV / Google TV APK
- `.sha256` — checksum for the APK
- `release-metadata-*.txt` — version, commit, build time, checksum
- `release-notes-*.md` — generated release notes

Download the bundle from the GitHub Releases page and verify the checksum before distributing:

```bash
sha256sum -c ImmichTV.v1.7.0-23.apk.sha256
```

## Signing

`android/key.properties` is intentionally not committed. When it is present locally, Gradle signs the release APK with `android/signing/upload-keystore.jks`. Without it, CI and fresh checkouts fall back to debug signing so builds still succeed. For a Play Store upload, provide the signing credentials through CI secrets / a local `key.properties` and verify the APK is signed with the expected key before publishing.

## Store submission

1. Complete `docs/ANDROID_TV_PACKAGING.md` and the TV device checklist.
2. Work through `docs/RELEASE_CHECKLIST.md` and capture the required screenshots.
3. Upload the APK or App Bundle, fill in the store listing using the GitHub repository description and topics, and attach the 320 x 180 TV banner.
4. Paste `docs/RELEASE_NOTES.md` highlights into the "What's new" field.
5. Publish to a staged rollout first, then monitor crashes and reviews before a full rollout.

## Post-release

- Confirm the GitHub release, tag, and APK checksum are correct.
- Confirm the Play listing shows the expected version and TV banner.
- Add any follow-up fixes to the next version bump; never reuse a build number.
