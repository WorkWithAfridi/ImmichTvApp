# Immich TV

<p align="center">
  <img src="assets/png/banner.png" alt="Immich TV banner" width="860">
</p>

TV-first Immich client for browsing your self-hosted photo and video library from the couch.

It connects to your existing Immich server and gives you a living-room experience designed for Android TV and Google TV first, built as a Flutter app for the wider platform matrix.

## Status

Immich TV is actively evolving and already usable as a focused TV browsing client.

Current product direction:

- Android TV / Google TV first
- Remote-first navigation and focus behavior
- Read-only browsing and playback
- Android TV packaging and release polish
- Better resilience for large libraries and degraded networks

## Features

- Connect to an existing Immich server
- Sign in with either your Immich login or an API token
- Save profiles locally for fast re-entry on shared TV devices
- Protect saved profiles with an optional 4-digit PIN, configurable from Settings
- Browse timeline assets in a TV-optimized layout
- Jump between years from a horizontal year rail
- Open albums, people, favorites, and memories
- Browse person-specific media from the People tab
- Revisit "On this day" and birthday memories as a fullscreen gallery
- View photos and videos fullscreen, with adaptive HLS streaming on supported servers
- Start slideshow playback directly from the viewer, continuously loading more photos as it goes
- Use a layout tuned for TV remotes, keyboards, and pointer input
- Detect the connected Immich server's version and enabled features so newer APIs are used only when supported
- Keep browsing already-loaded media during brief connection drops, with a retry action when the server returns
- Switch between live server access and demo content for testing

## Platform Focus

- Primary target: Android TV and Google TV
- Supported development targets: Android, web, Windows, macOS, and Linux
- UX priority: large-screen readability, predictable focus movement, and simple playback controls

## Server Compatibility

On sign-in, Immich TV probes `/server/version`, `/server/media-types`, and `/config` to learn which Immich version is running and which features the administrator has enabled. Newer APIs are used only when the server supports them; if discovery fails, the app falls back to the conservative feature set that works on older servers. Read requests use bounded retries for transient network failures, and the library keeps cached content available with an on-screen retry action when a refresh fails.

Memories use `GET /memories` when the server supports it. Adaptive HLS video is an opt-in setting under Settings → Playback because it is still an Alpha Immich API. It is used only on Immich v3+ native players; if the playlist cannot be opened, playback automatically falls back to the existing transcoded and original sources. Streaming sessions are released when playback stops. Browsers keep using the direct/transcoded sources because native HLS support varies by browser.

## Tech Stack

- Flutter
- Dart 3.11
- `flutter_bloc`
- Dio
- `flutter_secure_storage`
- `shared_preferences`
- `video_player`

## Current Version

- App version: `1.5.0+21`

## Getting Started

### Requirements

- Flutter SDK
- An accessible Immich server
- A target device such as Android TV, Google TV, emulator, or desktop for development

### Run locally

```bash
flutter pub get
flutter run
```

### Quality checks

```bash
flutter analyze
flutter test
```

## Demo Access

Immich TV includes a built-in demo mode for testing.

Enter this exact server URL in the onboarding flow:

```text
https://demo.immichtv.local
```

Then sign in with:

```text
Email: demo@immich.tv
Password: demo1234
```

Demo content is only triggered when that exact URL is entered.

## Repository Map

- `lib/main.dart`: app startup and image cache tuning
- `lib/app.dart`: dependency wiring, theme setup, repository injection
- `lib/src/app_shell.dart`: top-level flow between bootstrap, onboarding, profile picker, and home
- `lib/src/core`: shared models, repositories, networking, services, and logging
- `lib/src/features`: feature-specific UI, Cubits, and data implementations
- `lib/src/shared`: shared presentation tokens, focus helpers, and reusable widgets
- `lib/src/platform`: platform-aware persistence and media adapters
- `test/`: widget and focused unit coverage
- `docs/DEVELOPMENT_CHECKLIST.md`: roadmap and current execution slices

## Screens and Branding

The repository includes packaged brand assets under `assets/png/`.

- `banner.png`
- `tv-banner-icon.png`

## Roadmap

- Measure and tune scroll smoothness on real TV hardware
- Add browser-side HLS support for platforms without native playback
- Profile thumbnail rebuilds on real TV hardware
- Expand remote-navigation and integration test coverage
- Finish Android TV packaging and broader platform validation
- Continue polishing releases and documentation

## Contributing

Contributions, issues, and suggestions are welcome.

If you want to contribute:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `flutter analyze`
5. Run `flutter test`
6. Open a pull request

## Disclaimer

Immich TV is an independent client project and is not an official Immich app. You must already run or have access to an Immich server to use it.

## License

This project is licensed under the MIT License.

See [LICENSE](LICENSE) for details.
