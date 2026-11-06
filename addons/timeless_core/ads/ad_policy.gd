class_name AdPolicy
extends RefCounted
## When an interstitial may show (bible §3.1; Christopher, 2026-11-06):
##   - only at a break after a finished game: Play again (games on this
##     device), Main menu, New opponent. Never during a game.
##   - at most one every MIN_GAMES finished games, so never after the first
##     game of a session;
##   - at least MIN_GAP_MS apart, and not in the first MIN_GAP_MS after the
##     app starts. A rewarded video counts as an ad for the gap.
## Rematches against another player never show one (the caller skips the
## break), so a player who paid for no ads never waits on the other's ad.
## Pure logic: the time is passed in, so tests run it without waiting.

const MIN_GAMES := 2
const MIN_GAP_MS := 180_000

## Finished games since the last interstitial (or since the app started).
var games_since_ad := 0
## When the last ad closed (ms, Time.get_ticks_msec), or when the app started.
var last_ad_ms := 0


func _init(start_ms := 0) -> void:
	last_ad_ms = start_ms


func game_finished() -> void:
	games_since_ad += 1


## True when the next break after a game should show an interstitial.
func interstitial_due(now_ms: int) -> bool:
	return games_since_ad >= MIN_GAMES and now_ms - last_ad_ms >= MIN_GAP_MS


## An interstitial was shown: the count starts again.
func interstitial_shown(now_ms: int) -> void:
	games_since_ad = 0
	last_ad_ms = now_ms


## A rewarded video was watched: the next interstitial waits the full gap.
func rewarded_shown(now_ms: int) -> void:
	last_ad_ms = now_ms
