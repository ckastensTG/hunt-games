extends Node
## Stands in for the AdMob plugin's Admob node (addons/AdmobPlugin/Admob.gd)
## in tests of AdmobAdBackend: the same properties, methods and signals it
## uses. It only records the calls; the test plays Google's side by emitting
## the signals.

signal initialization_completed(status_data: Variant)
signal interstitial_ad_loaded(ad_info: Variant, response_info: Variant)
signal interstitial_ad_failed_to_load(ad_info: Variant, error_data: Variant)
signal interstitial_ad_failed_to_show_full_screen_content(ad_info: Variant, error_data: Variant)
signal interstitial_ad_dismissed_full_screen_content(ad_info: Variant)
signal rewarded_ad_loaded(ad_info: Variant, response_info: Variant)
signal rewarded_ad_failed_to_load(ad_info: Variant, error_data: Variant)
signal rewarded_ad_failed_to_show_full_screen_content(ad_info: Variant, error_data: Variant)
signal rewarded_ad_dismissed_full_screen_content(ad_info: Variant)
signal rewarded_ad_user_earned_reward(ad_info: Variant, reward_data: Variant)
signal consent_form_loaded
signal consent_form_dismissed(error_data: Variant)
signal consent_form_failed_to_load(error_data: Variant)
signal consent_info_updated
signal consent_info_update_failed(error_data: Variant)
signal tracking_authorization_granted
signal tracking_authorization_denied

class FakeAdInfo:
	extends RefCounted
	var id := ""
	func _init(ad_id: String) -> void:
		id = ad_id
	func get_ad_id() -> String:
		return id

var is_real := false
var max_ad_content_rating := 0
var remove_interstitial_ads_after_displayed := false
var remove_rewarded_ads_after_displayed := true
var debug_geography := -1
var test_device_hashed_ids: Array[String] = []
var android_debug_interstitial_id := ""
var android_debug_rewarded_id := ""
var android_real_interstitial_id := ""
var android_real_rewarded_id := ""
var ios_debug_interstitial_id := ""
var ios_debug_rewarded_id := ""
var ios_real_interstitial_id := ""
var ios_real_rewarded_id := ""

## The plugin's UserConsent.Status: UNKNOWN, NOT_REQUIRED, REQUIRED, OBTAINED.
var consent := 0
var form_available := true
var interstitial_loaded := false
var rewarded_loaded := false
## Method names in call order.
var calls: Array[String] = []


func count(method: String) -> int:
	return calls.count(method)


func update_consent_info(_params: Variant = null) -> void:
	calls.append("update_consent_info")


func get_consent_status() -> Variant:
	return {"status": consent}


func is_consent_form_available() -> bool:
	return form_available


func load_consent_form() -> void:
	calls.append("load_consent_form")


func show_consent_form() -> void:
	calls.append("show_consent_form")


func reset_consent_info() -> void:
	calls.append("reset_consent_info")
	consent = 0


func initialize() -> void:
	calls.append("initialize")


func request_tracking_authorization() -> void:
	calls.append("request_tracking_authorization")


func load_interstitial_ad(_request: Variant = null) -> void:
	calls.append("load_interstitial_ad")


func is_interstitial_ad_loaded() -> bool:
	return interstitial_loaded


func show_interstitial_ad(_id := "") -> void:
	calls.append("show_interstitial_ad")


func remove_interstitial_ad(_id := "") -> void:
	calls.append("remove_interstitial_ad")
	interstitial_loaded = false


func load_rewarded_ad(_request: Variant = null) -> void:
	calls.append("load_rewarded_ad")


func is_rewarded_ad_loaded() -> bool:
	return rewarded_loaded


func show_rewarded_ad(_id := "") -> void:
	calls.append("show_rewarded_ad")


func remove_rewarded_ad(_id := "") -> void:
	calls.append("remove_rewarded_ad")
	rewarded_loaded = false
