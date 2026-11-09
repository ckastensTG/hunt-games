extends TestCase
## The message the Share button sends with a friend code (play_menu.gd):
## the game's name, the code, and the menu path to enter it.

const Menu := preload("res://scenes/play/play_menu.gd")


func test_message_names_the_game_and_the_way_in() -> void:
	var text: String = Menu.share_message("TG-7K4Q", "bagh_chal")
	var lines := text.split("\n")
	check_eq(lines.size(), 2, "two lines")
	check_eq(lines[0], "Play Bagh Chal with me! My game code is TG-7K4Q.", "the game and the code")
	check_eq(lines[1], "Play online › Play with a friend › Enter a code", "the buttons to press")
