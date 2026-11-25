# Release Notes

## Unreleased (phone pairing preview)

- **Phone remote** — pair a phone from Settings and use a touch D-pad, Select/Back, text entry, and playback controls to drive the TV.
- **Continue as remote after setup** — a phone-assisted onboarding session can be reused as the remote session without re-pairing.
- **Session feedback and revoke** — encrypted acknowledgements, connected/expired/disconnected states, and an immediate Disconnect action on the TV.
- **Hardening** — foreground-only commands, sequence/replay/rate limits, app-background teardown, and narrow app-level action dispatch instead of raw key injection.
- **Release gates** — security review of the plain local transport and real-device validation are still required before this ships. The companion page is now bundled and hosted by the TV app itself, so no external deployment is needed.

## 1.7.0+23

Highlights for this release:

- **Video mute control** — a focusable mute/unmute button sits beside play/pause and applies to native and web playback.
- **Remote-first slideshow setup** — rebuilt as a D-pad-driven dialog with a single horizontally scrolling interval row, explicit focus states, and a full-width Cancel button.
- **More intervals** — 2, 3, 5, 8, 12, 20, 30, 45, and 60 seconds, with the last choice remembered.
- **Leaner web build** — the embedded marketing landing page and its `/app` gate were removed; the app now loads directly at `/`.
- **Docs and QA** — release checklist and web metadata updated to match the streamlined app.

## 1.6.0+22

Highlights for this release:

- **Continuous slideshow** — playback now loads the next paginated page near the end instead of looping over the initially loaded photos.
- **Places tab** — browse photos by city using Immich's map data, with a location rail and date-grouped grid.
- **Asset info overlay** — press `i` in the viewer for EXIF data, metadata, and OCR-detected text.
- **Brand refresh** — animated drawn flower splash, purple accent theme, ambient background, and a quieter near-black palette.
- **Drawer organization** — Library and Account sections, with a compact profile header on narrow screens.
- **Display care** — the wallpaper clock drifts slowly to reduce OLED burn-in.
- **Expanded tests** — coverage for slideshow paging, Places, asset info, and the new splash/theme components.

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
