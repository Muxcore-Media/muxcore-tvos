# MuxCore TV — hardware validation checklist

Manual soak on a **physical Apple TV** against a live vault stack (`https://mux.zem.systems` or your household URL). Run through this list before treating the tvOS client as household-ready. CI only ships an **unsigned** IPA; device validation requires Xcode signing on a Mac.

## Prerequisites

- Mac with Xcode 15+ and a valid Apple Developer account
- Apple TV on tvOS 17+ paired in **Window → Devices and Simulators**
- Network reachability to the MuxCore BFF (ZeroTier or LAN)
- Test member account, or Quick Connect / username-password from admin-ui

## Signed install (development)

Origin Forgejo CI (`.forgejo/workflows/ci.yml`) runs `swift test` in `Packages/MuxCoreAPI` only. GitHub `tvos-ipa.yml` builds an **unsigned** device IPA — not installable without re-signing.

For on-device validation:

1. `cd media-tvos-app && xcodegen generate && open MuxCoreTV.xcodeproj`
2. Set **Signing & Capabilities** → Team (bundle ID `systems.zem.muxcore.tv`)
3. Select your paired Apple TV as run destination → **⌘R** (Xcode signs automatically)
4. Alternatively: download CI `MuxCoreTV-unsigned.ipa`, re-sign with your tvOS provisioning profile, install via Apple Configurator

## BFF smoke (no TV required)

```bash
./scripts/bff-soak.sh
# optional authenticated walk:
MUX_TV_USER=you MUX_TV_PASS=secret ./scripts/bff-soak.sh
```

Anonymous: `/`, `/api/capabilities`, Quick Connect register. With credentials or `MUX_SESSION`, also walks `/api/movies`, `/api/tv`, `/api/userdata/progress`.

Full edge smoke: `_mvp/scripts/smoke-vault-public.sh`.

## Checklist (physical Apple TV)

| Step | Action | Pass |
|------|--------|------|
| Login | Quick Connect or username/password on login screen; session persists across relaunch | ☐ |
| Home | Hero + Continue Watching + Next Up shelves load | ☐ |
| Movies / TV | Open title detail; metadata and poster render | ☐ |
| Search | Global search returns results; request flow works when capability enabled | ☐ |
| Play video | Start movie or episode; AVPlayer plays resolve/transcode URL | ☐ |
| Resume | Exit mid-play; re-open title resumes near prior position | ☐ |
| Autoplay next | Finish episode with autoplay enabled; next episode starts | ☐ |
| Subtitles | Select subtitle track during playback when available | ☐ |
| More menu | Discover, Collections, Playlists, Queue, Favorites respect `GET /api/capabilities` | ☐ |
| Settings | Change home/playback/subtitle prefs; confirm sync via `/api/userdata` on web or second device | ☐ |
| Sign out | Sign out clears local session; relaunch shows login | ☐ |

## Notes

- Auth: `POST /api/tv/login` or Quick Connect; Bearer token stored in Keychain (`KeychainStore.swift`).
- Parity reference: `media-ui-app` routes in `AGENTS.md`; API types in `Packages/MuxCoreAPI`.
- Linux hosts cannot build the tvOS app; run `swift test` in `Packages/MuxCoreAPI` only.
