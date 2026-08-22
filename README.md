# MuxCore TV (Apple TV)

[![tvOS build](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-build.yml/badge.svg)](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-build.yml)
[![tvOS IPA](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-ipa.yml/badge.svg)](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-ipa.yml)

Native tvOS client for the MuxCore consumer stack — **feature parity** with `media-ui-app` against the same **mediauiprox** BFF (`https://mux.zem.systems`).

## Feature parity (vs media-ui-app)

| Area | Supported |
|------|-----------|
| Auth | Quick Connect, username/password (`/api/tv/login`), Bearer session |
| Libraries | Movies, TV, Music, Books, Comics, Audiobooks, Music Videos, Home Videos, Mixed |
| Features | Search + request, Discover detail, Collections, Studios, Upcoming, In Progress, Playlists, Queue, Live TV, Favorites |
| Home | Hero, Continue Watching, Next Up, Recommended, Favorites shelves |
| Playback | Resolve/transcode URL, resume position, progress sync (`/api/userdata`), autoplay next episode |
| Settings | Home/playback/subtitle/display prefs (synced via userdata) |
| Capabilities | `GET /api/capabilities` drives visible tabs and More menu |

## Build (macOS + Xcode 15+, tvOS 17+)

```bash
cd media-tvos-app
xcodegen generate
open MuxCoreTV.xcodeproj
```

### Linux — API package only

The `nixpkgs#swift` toolchain may fail to build on some hosts (e.g. clang rejects `-mtls-dialect=gnu2`). **tvOS app verification requires macOS + Xcode.** On Linux you can try:

```bash
cd media-tvos-app/Packages/MuxCoreAPI
nix shell nixpkgs#swift --command swift test
```

If that nix build fails, use a Mac for Swift compile/test; Go BFF tests (`mediauiprox`) still run on Linux.

## CI artifacts (unsigned device IPA)

The [**tvOS IPA**](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-ipa.yml) workflow builds a **Release device** binary (`appletvos`), packages it as `MuxCoreTV-unsigned.ipa`, and uploads it as a GitHub Actions artifact on every push to `main`.

**Download:** open the latest green [tvOS IPA run](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-ipa.yml) → **Artifacts** → `MuxCoreTV-ipa` → unzip to get `MuxCoreTV-unsigned.ipa`.

The [**tvOS build**](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-build.yml) workflow is compile-only (tvOS Simulator). It does **not** produce an installable file for a physical Apple TV.

### Install on Apple TV

CI IPAs are **unsigned**. You cannot install them on a TV as-is — Apple requires a valid code signature (Apple Developer account).

| Method | When to use |
|--------|-------------|
| **Xcode Run (⌘R)** | Easiest for development. Pair your Apple TV (Window → Devices and Simulators), select it as the run destination, build & run. Xcode signs with your team automatically. |
| **Re-sign CI IPA** | Download `MuxCoreTV-unsigned.ipa`, re-sign with your development/distribution cert + tvOS provisioning profile, then install via [Apple Configurator](https://support.apple.com/apple-configurator) or your usual sideload tool (tvOS support varies by tool). |
| **Local Release IPA** | On a Mac, after `xcodegen generate`, archive or `xcodebuild -sdk appletvos -configuration Release` with your signing team set in Xcode; package `Payload/MuxCoreTV.app` into an IPA the same way CI does. |

Bundle ID: `systems.zem.muxcore.tv` (display name **MuxCore**). Minimum tvOS **17.0**.

### What is `Packages/MuxCoreAPI`?

Not an app — a **Swift package** (shared library) used by the tvOS app:

- `Client.swift` — HTTP client for the mediauiprox BFF (`https://mux.zem.systems`)
- `Models.swift` — JSON types (`Movie`, `TVShow`, userdata, playback, etc.)

Same role as `media-ui-app/src/api/client.ts`. The installable app target is **MuxCoreTV**; MuxCoreAPI is linked into it at build time.

## Project layout

```
media-tvos-app/
  Packages/MuxCoreAPI/     # Shared client + models (mirrors media-ui-app/src/api)
  MuxCoreTV/Sources/
    Services/              # UserdataStore, Acquisition, PlaybackCoordinator, NavCatalog
    Views/                 # SwiftUI screens matching web routes
    Components/
  project.yml
```

## Related

- Web client: `media-ui-app/`
- BFF: `_mvp/cmd/mediauiprox/`
