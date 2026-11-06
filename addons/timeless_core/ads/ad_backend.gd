class_name AdBackend
extends Node
## Where ads come from. AdService picks one when it starts:
##   AdmobAdBackend  Google AdMob through the AdMob plugin (phones);
##   SimAdBackend    test builds without AdMob (desktop, the editor): a
##                   labelled stand-in, so placement, caps and rewards can be
##                   tried without a phone;
##   AdBackend       this one: no ads at all (desktop release, Steam, tools).
## Each ad that is asked for ends with exactly one closed signal, also when
## it couldn't show (shown = false).

## Something an ad screen shows changed: an ad became ready, consent settled.
signal changed
signal interstitial_closed(shown: bool)
signal rewarded_closed(earned: bool, shown: bool)


## "none", "sim" or "admob".
func kind() -> String:
	return "none"


## `setup` (AdService.start): {interstitial, rewarded: ad unit IDs,
## debug: bool, test_devices: Array of hashed device IDs}.
func start(_setup: Dictionary) -> void:
	pass


func interstitial_ready() -> bool:
	return false


func show_interstitial() -> void:
	interstitial_closed.emit.call_deferred(false)


func rewarded_ready() -> bool:
	return false


func show_rewarded() -> void:
	rewarded_closed.emit.call_deferred(false, false)


## True where the player can change their ad consent (the EEA, the UK,
## Switzerland: wherever Google's consent form was required).
func privacy_options_available() -> bool:
	return false


## Shows the consent form again, so the player can change their choice.
func show_privacy_options() -> void:
	pass
