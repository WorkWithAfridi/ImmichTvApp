# Release Notes

## 1.5.0+21

Highlights for this release:

- **Memories tab** — "On this day" and birthday memories grouped into one folder per year, with photos grouped by date inside each year.
- **Server capability detection** — Immich TV checks the server version and enabled features at sign-in and only calls newer APIs when supported.
- **Resilient browsing** — bounded retries for read requests and image loads, an offline banner with manual retry, and cached content that stays browsable during network drops.
- **Adaptive video** — optional HLS playback on Immich v3+ servers with automatic fallback and explicit session cleanup.
- **Integration coverage** — end-to-end onboarding, browse, profile switch, and sign-out tests.
- **Android TV packaging** — documented launcher metadata, banner assets, build commands, and a device checklist.
- **Performance tooling** — rebuild counters and an opt-in HUD (`--dart-define=immichtv.profile=true`) plus density-aware thumbnail prefetching.

## 1.4.x

- Saved profiles with optional PIN protection and an on-screen keyboard.
- Timeline, albums, people, favorites, fullscreen viewer, and slideshow.
- Demo mode for previewing the app without a private Immich server.
