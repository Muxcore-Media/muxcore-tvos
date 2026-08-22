# AGENTS.md — MuxCore Apple TV client

Native **tvOS** consumer app at **parity with `media-ui-app`**. Uses **mediauiprox** only — never module gRPC/HTTP directly.

## Parity checklist

Mirror `media-ui-app/src/App.tsx` routes and `lib/nav-catalog.ts` visibility:

- Libraries: movies, tv, music, books, comics, audiobooks, homevideos, musicvideos
- Features: search, request, collections, studios, upcoming, mixed, livetv, quickconnect, playlists, queue, favorites
- Userdata: progress, favorites, prefs, playlists, queue via `/api/userdata` (see `UserdataStore.swift`)
- Playback: `/api/playback/resolve`, subtitles list, resume + scrobble

## Key paths

| Piece | Path |
|-------|------|
| API client | `Packages/MuxCoreAPI/` |
| Userdata | `MuxCoreTV/Sources/Services/UserdataStore.swift` |
| Capabilities nav | `MuxCoreTV/Sources/Services/NavCatalog.swift` |
| Views | `MuxCoreTV/Sources/Views/` |

## Build

- tvOS app: macOS + `xcodegen generate`
- API tests on Linux: `nix shell nixpkgs#swift --command swift test` in `Packages/MuxCoreAPI`

## Deploy

Client-only repo path. BFF changes (`quickconnect`, `tv/login`, Bearer) require **mediauiprox** redeploy on vault per workspace `AGENTS.md`.
