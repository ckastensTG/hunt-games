class_name GameText
extends RefCounted
## The player's text size: Normal or Large (Settings → Large text), saved per
## device with the other settings (user://settings.cfg). Large makes every
## text a quarter bigger (SeriesTheme.fs). Christopher, 2026-11-08: "normal"
## and "large" with a significant difference between the two.

const SETTING := "text_large"


static func apply_saved() -> void:
	SeriesTheme.set_large(bool(L10n.load_setting(SETTING, false)))


static func is_large() -> bool:
	return SeriesTheme.large


## Saves the choice and rebuilds every screen at the new size: the menus,
## the in-game display and the match overlay rebuild themselves when told
## the text changed, the same way as for a new language.
static func set_large(on: bool, tree: SceneTree = null) -> void:
	L10n.save_setting(SETTING, on)
	if on == SeriesTheme.large:
		return
	SeriesTheme.set_large(on)
	if tree:
		tree.root.propagate_notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
