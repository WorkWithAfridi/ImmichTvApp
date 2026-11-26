# Release Notes

## 2.0.0+24

Highlights for this release:

- **Phone setup from the TV** — a third input-method card lets you enter the Immich server URL and sign-in details on a phone instead of typing them with the TV remote.
- **TV-hosted companion** — the TV serves the phone page itself, so scanning the QR connects directly with no external site or deployment.
- **Direct connection** — scanning connects immediately; there is no approval code or confirmation step on the TV.
- **Multiple phones** — several phones can connect to the same TV and control it at once, each with its own command sequence.
- **Phone remote** — a touch D-pad, Select/Back, text entry, and playback controls drive the TV from Settings or after setup.
- **Focus and layout fixes** — the phone action is reachable by D-pad in Settings, the pairing dialog scales with the viewport, and sidebar navigation is cleaner.
- **Local transport** — details and commands travel over the trusted local network without transport encryption; TV keyboard entry remains the fallback.
- **Release gates** — security review of the plain local transport and real-device validation are still required.

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
