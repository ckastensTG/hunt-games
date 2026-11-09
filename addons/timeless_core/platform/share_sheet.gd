class_name ShareSheet
extends RefCounted
## The system share sheet for a short text (a game code and how to use it),
## with no plugin to install:
##   - Android: an ACTION_SEND chooser made through Godot's Java wrapper.
##   - iPhone and iPad: platform/ios/TimelessShare.m, which timeless_core's
##     export step (editor/ios_native_sources.gd) adds to the Xcode project.
##     The game reaches it with OS.shell_open("timelessshare:?text=…"); the
##     native file catches that address before iOS would look for an app to
##     open it, and shows Apple's share sheet instead.
##   - Elsewhere (desktop, the editor, tools): share() returns false and the
##     caller copies the text.

const IOS_SCHEME := "timelessshare"


## Whether this platform has a share sheet.
static func available() -> bool:
	match OS.get_name():
		"Android":
			return Engine.has_singleton("AndroidRuntime")
		"iOS":
			return true
	return false


## Shows the share sheet with `text`; `title` is the Android chooser's
## heading. False when there's no sheet here or it couldn't open.
static func share(text: String, title := "") -> bool:
	match OS.get_name():
		"Android":
			return _android(text, title)
		"iOS":
			return OS.shell_open(ios_url(text)) == OK
	return false


## The address the native iOS file answers: timelessshare:?text=<encoded>.
static func ios_url(text: String) -> String:
	return "%s:?text=%s" % [IOS_SCHEME, text.uri_encode()]


static func _android(text: String, title: String) -> bool:
	if not Engine.has_singleton("AndroidRuntime"):
		return false
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	var intent_class = JavaClassWrapper.wrap("android.content.Intent")
	if activity == null or intent_class == null:
		return false
	# A constructor is called by the class's own name (JavaClassWrapper).
	var intent = intent_class.Intent("android.intent.action.SEND")
	if intent == null:
		return _failed("no intent")
	intent.setType("text/plain")
	intent.putExtra("android.intent.extra.TEXT", text)
	var chooser = intent_class.createChooser(intent, title)
	if chooser == null:
		return _failed("no chooser")
	activity.startActivity(chooser)
	return _failed("startActivity") if JavaClassWrapper.get_exception() != null else true


static func _failed(step: String) -> bool:
	var err = JavaClassWrapper.get_exception()
	push_warning("Share sheet: %s%s" % [step, (" (%s)" % err) if err != null else ""])
	return false
