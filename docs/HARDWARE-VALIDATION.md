# Physical Apple TV validation

CI builds an **unsigned** device IPA only. Household-ready tvOS requires a one-time pass on real hardware with a signed build.

## Prerequisites

- Mac with Xcode 15+ and an Apple Developer team
- Apple TV (tvOS 17+) on the same network, paired in **Window → Devices and Simulators**
- MuxCore stack reachable at `https://mux.zem.systems` (or your vault edge URL)

## Pre-flight (automated, no Apple TV)

```bash
./scripts/bff-soak.sh
# optional full API walk (vault soak: source secrets.env → MVP_ADMIN_USER / MVP_ADMIN_PASSWORD):
TV_SOAK_USERNAME=... TV_SOAK_PASSWORD=... ./scripts/bff-soak.sh
# TOTP accounts: TV_SOAK_TOTP_CODE=... after password step returns requires_2fa
```

## Validation checklist

Run on device via **Xcode Run (⌘R)** with bundle `systems.zem.muxcore.tv`.

| # | Flow | Pass criteria |
|---|------|----------------|
| 1 | Quick Connect login | Approves code; lands on Home |
| 2 | Username/password login | `POST /api/tv/login` succeeds; session persists across relaunch |
| 3 | Home shelves | Continue Watching, Next Up, Favorites load without error |
| 4 | Browse + detail | Movies and TV detail pages open; request button works when entitled |
| 5 | Search + discover | Query returns library + remote hits; discover detail request works |
| 6 | Playback | Resolve starts stream; resume position updates after exit/re-enter |
| 7 | Subtitles | Subtitle list loads when module enabled; preferred language applies |
| 8 | Live TV tab | Visible only when `capabilities.livetv`; guide loads |
| 9 | Settings sync | Change playback/subtitle prefs; confirm via web `media-ui-app` userdata |
| 10 | Sign out / re-auth | Session clears; login required again |

## Sign-off

Record in an issue or ops log:

```
Date:
Apple TV model / tvOS version:
Xcode / team:
Server URL:
Validator:
Checklist: all PASS / failures noted
```

When all rows pass, remove the **`media-tvos-app`** row from `MASTER-ROADMAP.md` §1.

## CI artifact path (unsigned)

Download `MuxCoreTV-unsigned.ipa` from the latest green [tvOS IPA workflow](https://git.zem.systems/muxcore/media-tvos-app/actions), re-sign with your development cert, install via Apple Configurator or Xcode Devices.
