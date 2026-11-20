# Release Notes

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
