# MuxCore TV (Apple TV)

[![tvOS build](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-build.yml/badge.svg)](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-build.yml)
[![tvOS IPA](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-ipa.yml/badge.svg)](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-ipa.yml)

Native tvOS client for the MuxCore consumer stack, targeting feature parity with `media-ui-app` through the configured **mediauiprox** BFF. The feature inventory below is source scope, not native runtime or cross-device acceptance.

## Feature parity (vs media-ui-app)

| Area | Supported |
|------|-----------|
| Auth | Quick Connect, username/password (`/api/tv/login`), Bearer session |
| Libraries | Movies, TV, Music, Books, Comics, Audiobooks, Music Videos, Home Videos, Mixed |
| Features | Search + request, Discover detail, Collections, Studios, Upcoming, In Progress, Playlists, Queue, Live TV, Favorites |
| Home | Hero, Continue Watching, Next Up, Recommended, Favorites shelves |
| Playback | Resolve/transcode URL, resume position, progress sync (`/api/userdata`), autoplay next episode |
| Settings | Home/playback/subtitle/display prefs, visible userdata sync status and retry |
| Capabilities | `GET /api/capabilities` drives visible tabs and More menu |

## Build (macOS + Xcode 15+, tvOS 17+)

```bash
cd media-tvos-app
xcodegen generate
open MuxCoreTV.xcodeproj
```

### Linux — API and userdata sync package

With a system Swift toolchain, run the HTTP fixtures and the same userdata sync state machine used by the app:

```bash
cd media-tvos-app/Packages/MuxCoreAPI
swift test --jobs 2
```

On Nix hosts, the equivalent command is:

```bash
cd media-tvos-app/Packages/MuxCoreAPI
nix shell nixpkgs#swift --command swift test
```

**tvOS app compilation and runtime verification require macOS + Xcode.** Package fixtures do not launch the app, a BFF, or userdata-local. The `nixpkgs#swift` build can fail on some hosts (for example, clang rejecting `-mtls-dialect=gnu2`); use an available supported Swift toolchain in that case.

## Userdata sync and its limits

The app sends BFF bearer requests with cookie handling disabled. It verifies the existing `/api/session` identity before the first userdata exchange in a binding. Saved data and pending revisions are stored together in an account record keyed by server origin, verified tenant and stable user ID. A previously verified saved session can use its own offline cache; a new or legacy unverified session must connect before attaching a cache or editing userdata. Signing out clears visible data while retaining that account's pending record. Ownerless legacy keys (`muxcore.progress`, `muxcore.favorites`, etc.) are preserved but never assigned to the next login.

Writes retain pending changes through HTTP/decoding failures, relaunch, overlapping reads/writes, logout and account changes. One network flight is drained before a new binding writes. Before each PUT the client reads the current blob, retains local dirty fields, and includes all replacement sections (preferences, playlists and queue), because the provider defaults omitted sections. Only edited progress/favorite entries are sent. Preference edits rebase changed leaves onto the latest document and retain unknown client fields. Responses must match the verified account and submitted changes before those revisions are cleared. Settings offers retry; sign-in, foregrounding and later changes also trigger a bounded attempt. Failures are shown in the main shell.

These fixtures establish client behavior, with the following remaining limits:

- “Server acknowledged” means a matching BFF response, not verified provider or cross-device persistence. The BFF can use local fallback; Quick Connect remains supported but may lack an upstream provider bearer. T-M4-09 and S9b track the real-provider path and runtime gates.
- The existing BFF/provider favorite maps merge by ID and expose no deletion operation. Unconfirmed removals stay local and pending with an explicit message; retry cannot add a missing server capability.
- Userdata tenant metadata must agree with the verified session. Configurations that omit or substitute a tenant fail closed and retain pending data; full multi-tenant integration is unverified.
- The protocol has no compare-and-swap revision. Fresh reads and local revisions prevent this app's known response races, but cannot make concurrent replacements from different devices atomic or resolve an uncertain server write after a lost response.
- The client preserves unknown preferences on the wire and in its cache. A provider using its narrower typed preferences model can still discard unknown fields; that backend contract remains separate work.
- The local record uses `UserDefaults` and is intended to survive normal relaunch, not device storage purges or uninstall. A detected encoding/storage error keeps edits in memory and warns to keep the app open. This is not a backup or a verified tvOS process-restart test.

## CI artifacts (unsigned device IPA)

The [**tvOS IPA**](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-ipa.yml) workflow runs manually or on `v*` release tags. It builds a **Release device** binary (`appletvos`), packages it as `MuxCoreTV-unsigned.ipa`, and uploads a GitHub Actions artifact.

**Download:** open the latest green [tvOS IPA run](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-ipa.yml) → **Artifacts** → `MuxCoreTV-ipa` → unzip to get `MuxCoreTV-unsigned.ipa`.

The [**tvOS build**](https://github.com/Muxcore-Media/muxcore-tvos/actions/workflows/tvos-build.yml) workflow also runs manually or on `v*` tags. It tests MuxCoreAPI, then compiles for tvOS Simulator. It does **not** launch a simulator test or produce an installable file for a physical Apple TV.

### Install on Apple TV

CI IPAs are **unsigned**. You cannot install them on a TV as-is — Apple requires a valid code signature (Apple Developer account).

| Method | When to use |
|--------|-------------|
| **Xcode Run (⌘R)** | Easiest for development. Pair your Apple TV (Window → Devices and Simulators), select it as the run destination, build & run. Xcode signs with your team automatically. |
| **Re-sign CI IPA** | Download `MuxCoreTV-unsigned.ipa`, re-sign with your development/distribution cert + tvOS provisioning profile, then install via [Apple Configurator](https://support.apple.com/apple-configurator) or your usual sideload tool (tvOS support varies by tool). |
| **Local Release IPA** | On a Mac, after `xcodegen generate`, archive or `xcodebuild -sdk appletvos -configuration Release` with your signing team set in Xcode; package `Payload/MuxCoreTV.app` into an IPA the same way CI does. |

Bundle ID: `systems.zem.muxcore.tv` (display name **MuxCore**). Minimum tvOS **17.0**.

**Household validation:** see [`docs/HARDWARE-VALIDATION.md`](docs/HARDWARE-VALIDATION.md) for the physical Apple TV checklist.

### What is `Packages/MuxCoreAPI`?

Not an app — a **Swift package** (shared library) used by the tvOS app:

- `Client.swift` — HTTP client for the mediauiprox BFF (`https://mux.zem.systems`)
- `Models.swift` — JSON types (`Movie`, `TVShow`, userdata, playback, etc.)
- `UserdataSyncStore.swift` — account-bound cache, pending revisions, serialized sync and response checks

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
