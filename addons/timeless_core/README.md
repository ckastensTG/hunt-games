# timeless-core

Shared framework for **Timeless Games by Time Galleon**: the rules engine,
AI, test runner and (later) presentation, shell and platform services that
every title builds on.

This repo is a Godot 4 addon. Game projects include it as a git submodule at
`addons/timeless_core/`. Design: `claude/framework-architecture.md` in the
"Ancient games series" project.

## Contents

| Path | What it is |
|---|---|
| `rules/board_def.gd`, `rules/board_builder.gd` | Boards as points and polylines. Adjacency and jumps come from the lines, never from coordinates. |
| `rules/hunt/` | Hunt-game family (Bagh Chal, Adugo, Komikan, ...): `HuntRuleSet`, `HuntState` (move generation, make/unmake, repetition, terminal rules), Zobrist hashing, `HuntEvaluator`. |
| `ai/hunt_searcher.gd` | Alpha-beta with iterative deepening, transposition table and capture quiescence. Explicit stack: `step(nodes)` pauses and resumes. |
| `ai/ai_persona.gd` | Named opponents: search limits plus plausible (seeded) mistakes. |
| `ai/ai_driver.gd` | Runs one AI move on a worker thread (start, poll, cancel). |
| `match/match_session.gd` | `MatchSession`: one game in any mode (AI, pass and play, nearby, online). Validates every move, undo, resign/draw/forfeit endings, saves (setup + moves). |
| `net/` | Two-device play, protocol v1 (framework §9): `NetProtocol` (checked messages), `NetTransport` with ENet (local Wi-Fi) and loopback (tests), `NetMatch` (handshake, moves with position hash, resync, reconnect window, turn clock, draw/undo/rematch), `JoinCode` (nearby codes), `LanDiscovery` (Wi-Fi beacons). |
| `online/` | Online play behind `OnlineBackend` (the base class is "unavailable"): `QuickMatch` (search, host, merge rule), `FriendMatch` (TG-XXXX codes), `PlayerNames`, `FakeOnlineBackend` (in-process, for tests and debug builds), and EOS: `EOSOnlineBackend` with `EOSP2PTransport` on an `EOSApi`, implemented for the EOSG plugin by `eosg_api.gd` (loaded only when the plugin is in the project). |
| `audio/` | `AudioBuses` (the SFX and Music buses, on/off and volume), `SfxPlayer` (sounds by event name, several takes each, never the same take twice in a row, a little pitch variety) and `MusicPlayer` (a set of tracks in a shuffled order with pauses between them, a fade-over when the set changes, a duck under stings, paused while the Music bus is muted). |
| `render/` | `FrameTimer` (frame times over a window: mean, percentiles, stalls kept apart; for automatic graphics settings) and `PerfOverlay` (a frame-rate readout for testing on devices in any build: F3 or a three-finger tap; fps, frame times, GPU/CPU render time, draw calls, plus a line from the game). |
| `ads/` | Every ad goes through `AdService` (one per app, `AdService.instance()`): `AdPolicy` (an interstitial at most every 2nd finished game, 3+ minutes apart, only at a break after a game), rewarded videos with their result, "Remove ads" (saved), extras unlocked for the session, sound muted while an ad shows. Backends: `AdmobAdBackend` (Cengiz's AdMob plugin v7.0, loaded only when it runs on the device: Google's UMP consent first, then the SDK, one ad of each kind loaded ahead, retries and expiry; on iPhone and iPad the SDK starts before the consent form, which the plugin needs, and Apple's tracking prompt comes after consent, before any ad), `SimAdBackend` (a labelled stand-in for test builds without AdMob) and the no-ads base `AdBackend` (desktop release, Steam, headless tools). |
| `platform/` | `DeviceInfo`: facts Godot doesn't give directly, such as the Android API level. `OS.get_version()` returns the maker's build number on many phones, e.g. "30.66-3" on a moto g(20) running Android 11. |
| `iap/` | Every purchase goes through `IAPService` (one per app, `IAPService.instance()`): the store's price, buy and restore with their results, what the player owns (kept in `user://purchases.cfg`). Backends: `PlayBillingBackend` (the Godot Foundation's Google Play Billing plugin, Play Billing Library 9: acknowledges purchases, pending payments, owned purchases at start and on resume), `StoreKitBackend` (StoreKit 2 from Godot Apple Plugins: finishes transactions, current entitlements, AppStore.sync for Restore), `SimIapBackend` (a labelled test purchase sheet for test builds, and for test builds whose store has no product yet) and the no-store base `IapBackend`. |
| `plugin.cfg`, `editor/` | The editor plugin: its export step adds the EOS Android library and its AndroidX dependencies to Gradle builds, and on iOS exports with the AdMob plugin adds Google's Mobile Ads Swift package to the Xcode project (`admob_ios_spm.gd`; the plugin's own step needs a Ruby gem macOS lacks), and writes the permission prompts' translated texts into each language's `InfoPlist.strings` (`ios_plist_strings.gd`). |
| `testing/` | Headless test runner, `TestCase` base class, `FakeEOSApi` (a pretend EOS for tests) and `fake_admob.gd` (a stand-in for the AdMob plugin's node). |
| `tests/` | Core unit tests. |

## Requirements

Godot **4.7.2** (pinned for the series until M2; see the architecture doc).

## Running the tests

From a game project that includes this addon:

```sh
godot --headless --path . --import
godot --headless --path . -s res://addons/timeless_core/testing/test_runner.gd -- \
  --dir=res://addons/timeless_core/tests
```

CI does the same in a throwaway host project (`.github/workflows/ci.yml`).

Copyright © Time Galleon. All rights reserved.
