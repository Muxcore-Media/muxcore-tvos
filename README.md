# MuxCore TV (Apple TV)

[![tvOS build](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-build.yml/badge.svg)](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-build.yml)

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
