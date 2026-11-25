# Immich TV phone companion

This directory contains the static HTTPS page used by the TV's QR pairing flow. It has no build step, third-party scripts, analytics, storage, or service worker. Its Web Crypto implementation is covered by deterministic vectors shared with the Dart implementation.

## Deployment

The repository workflow `.github/workflows/deploy-phone-companion.yml` can be run manually from GitHub Actions. It publishes only this directory to the repository's GitHub Pages site. Configure GitHub Pages to use GitHub Actions before running it. Deployment is deliberately manual so a source change cannot silently update the security-critical page.

The app's default URL is `https://workwithafridi.github.io/immich_tv_app/phone_companion/`. If hosting this fork elsewhere, build the TV app with:

```text
--dart-define=PHONE_COMPANION_URL=https://your-controlled-host.example/path/
```

The configured URL must be HTTPS, contain no query or fragment, and serve these files without injecting third-party code. The configured URL's origin is also the exact CORS origin allowed by the TV listener. Keep the URL in sync with the deployed site.

## Browser and network behavior

The phone must load this page in a browser that supports Web Crypto X25519, then explicitly tap **Connect to TV**. The page contacts the TV directly over the same local network; it does not use Bluetooth or a cloud relay. Browser local-network permission prompts, guest Wi-Fi isolation, VPNs, and router client isolation may prevent this connection. The TV keyboard remains available as the fallback. Safari versions without Web Crypto X25519 support cannot use phone entry.

The QR invitation is in the URL fragment and is removed from browser history as soon as the page reads it. Credentials are sent only after the user compares the verification code and approves on the TV. The companion encrypts credentials before local-network transmission and clears its form fields after sending or on failure. The TV then validates the server and leaves sign-in under the user's control.

## Local checks

Run the companion crypto tests with `npm test --prefix phone_companion`. Run TV pairing tests with `flutter test test/src/features/remote_pairing`. Real Android Chrome and iOS Safari pairing, including permission prompts and credential round trips, still needs device validation before release.
