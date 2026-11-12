class_name StoreLinks
extends RefCounted
## A game's store page, opened from "Other Timeless Games". The addresses are
## built here from IDs GameList has checked, never taken from the list:
##   - Android: the Play Store app (market://details?id=<package>), else the
##     Play web page.
##   - iPhone and iPad: Apple's App Store sheet inside the game
##     (SKStoreProductViewController), through platform/ios/
##     TimelessStoreSheet.m, which timeless_core's export step adds to the
##     Xcode project; the game reaches it with OS.shell_open("timelessstore:
##     ?id=<Apple ID>"), as ShareSheet does. If the sheet can't show, the
##     native file opens the App Store page itself.
##   - Elsewhere (desktop, the editor): the store's web page.

const IOS_SCHEME := "timelessstore"


static func play_app_url(package: String) -> String:
	return "market://details?id=" + package


static func play_web_url(package: String) -> String:
	return "https://play.google.com/store/apps/details?id=" + package


static func app_store_web_url(apple_id: String) -> String:
	return "https://apps.apple.com/app/id" + apple_id


## The address the native iOS file answers: timelessstore:?id=<Apple ID>.
static func ios_sheet_url(apple_id: String) -> String:
	return "%s:?id=%s" % [IOS_SCHEME, apple_id]


## The addresses to try, in order, for a game available on `store`, on
## `platform` (OS.get_name()); [] when it isn't available there or its ID
## doesn't check out.
static func urls(entry: Dictionary, store: String, platform := OS.get_name()) -> PackedStringArray:
	var s: Dictionary = entry.get("stores", {}).get(store, {})
	if s.get("status", "") != "available":
		return PackedStringArray()
	match store:
		"google_play":
			var package := str(s.get("package", ""))
			if not GameList.valid_package(package):
				return PackedStringArray()
			if platform == "Android":
				return PackedStringArray([play_app_url(package), play_web_url(package)])
			return PackedStringArray([play_web_url(package)])
		"app_store":
			var apple_id := str(s.get("apple_id", ""))
			if not GameList.valid_apple_id(apple_id):
				return PackedStringArray()
			if platform == "iOS":
				return PackedStringArray([ios_sheet_url(apple_id), app_store_web_url(apple_id)])
			return PackedStringArray([app_store_web_url(apple_id)])
	return PackedStringArray()


## Opens the game's store page; false when nothing could be opened.
static func open(entry: Dictionary, store: String) -> bool:
	for url in urls(entry, store):
		if OS.shell_open(url) == OK:
			return true
	return false
