class_name HuntOrigins
extends RefCounted
## "Game origins": a short history of each title's game, opened from the main
## menu, with the main historical sources at the end (bible §8, the first part
## of the Codex). Every title supplies one; the menu hides the button for a
## title that has none yet.
##
## Paragraphs are translated whole; [i]…[/i] marks italics (RichTextLabel
## BBCode). Sources are shown as written, never translated: title of the work,
## author, publication (for an article or chapter), year. No links.
## Fact-checked 2026-11-04 against the sources listed; the Nepali consultant
## reviews the text before release.


static func has_text(title: String) -> bool:
	return not paragraphs(title).is_empty()


static func paragraphs(title: String) -> Array[String]:
	var out: Array[String] = []
	match title:
		"bagh_chal":
			# TRANSLATORS: "Game origins" text for Bagh Chal, paragraph 1 of 7. Keep the [i]…[/i] tags around the italic words. Bagh Chal and dhun kasa stay as they are.
			out.append(L10n.t("Bagh Chal comes from Nepal. Its name joins the Nepali words for “tiger” and “move”. Four tigers hunt twenty goats on a board of five by five points: the tigers capture goats by jumping over them, and the goats win by hemming the tigers in until none of them can move. In Nepal Bhasa, the language of the Newars of the Kathmandu Valley, the game is called [i]dhun kasa[/i], “the tiger game”."))
			# TRANSLATORS: "Game origins" text for Bagh Chal, paragraph 2 of 7. "Hunt games" is the board-game historians' name for this family. Keep [i]aadu puli attam[/i] as it is.
			out.append(L10n.t("It belongs to a large family of hunt games, in which a few strong pieces face many weak ones. Games of tigers against goats or lambs are played on many different boards across South Asia; in southern India, for example, the related [i]aadu puli attam[/i] has a board of its own."))
			# TRANSLATORS: "Game origins" text for Bagh Chal, paragraph 3 of 7. Parlett: David Parlett, a British games historian; write his name as in the termbase.
			out.append(L10n.t("No one knows how old the game is: it was handed down by playing, not in writing. Players often scratched the board into the ground or into stone and played with stones and pebbles. In 1976 the games historian David Parlett found it popular with Buddhist monks, who played it just that way."))
			# TRANSLATORS: "Game origins" text for Bagh Chal, paragraph 4 of 7. Bhagchal, Bhagchakar and Chakrachal are the names Hora recorded: keep them as they are. Averbakh: Yuri Averbakh, a Russian chess grandmaster.
			out.append(L10n.t("One of the earliest written descriptions dates from 1933, when the zoologist Sunder Lal Hora recorded the game in the Teesta valley of the eastern Himalayas as Bhagchal, Bhagchakar or Chakrachal, with four tigers and twenty goats. Parlett set down its rules in Nepal in 1976, and the chess grandmaster Yuri Averbakh, who saw it there in 1986, called it a national game, about as popular as chess."))
			# TRANSLATORS: "Game origins" text for Bagh Chal, paragraph 5 of 7. "Standard" and "Parlett 1976" are the names of this game's two rule sets: use the same words as in the rules menu.
			out.append(L10n.t("The old accounts don't all end the hunt at the same point. Hora and Parlett have the tigers hunt down every goat, while most players today stop at five captures. This game offers both: the Standard rules, with five, and Parlett 1976, the hunt to the last goat."))
			# TRANSLATORS: "Game origins" text for Bagh Chal, paragraph 6 of 7. Lim Yew Jin and Jürg Nievergelt are computer scientists; "a draw" is a game with no winner.
			out.append(L10n.t("In 2004 the computer scientists Lim Yew Jin and Jürg Nievergelt set out to compute every position of the game. They later proved that with perfect play on both sides the standard game ends in a draw: neither the tigers nor the goats can force a win."))
			# TRANSLATORS: "Game origins" text for Bagh Chal, paragraph 7 of 7. A pati is a public rest-house in Nepal: keep the word, as the text explains it.
			out.append(L10n.t("In the Kathmandu Valley, older players still meet over the board on the platforms of the patis, the public rest-houses, and around temples, and metal and wooden boards are sold, mostly to visitors. Reporters in Kathmandu note that fewer young people play it today."))
	return out


## The main sources, oldest first, exactly as shown (not translated).
static func sources(title: String) -> Array[String]:
	var out: Array[String] = []
	match title:
		"bagh_chal":
			out.assign([
				"“Sedentary games of India”, Sunder Lal Hora, [i]Journal and Proceedings of the Asiatic Society of Bengal[/i], 1933",
				"“Himalayan Games”, David Parlett, [i]Games & Puzzles[/i], 1976",
				"“Board Games and Real Events”, Yuri Averbakh, [i]New Approaches to Board Games Research[/i], 1995",
				"[i]The Oxford History of Board Games[/i], David Parlett, 1999",
				"“Computing Tigers and Goats”, Lim Yew Jin & Jürg Nievergelt, [i]ICGA Journal[/i], 2004",
				"“Tigers and Goats is a draw”, Lim Yew Jin & Jürg Nievergelt, [i]Games of No Chance 3[/i], 2009",
				"“Bagh Chal: A native board game on the brink of extinction”, Shranup Tandukar, [i]The Kathmandu Post[/i], 2021",
			])
	return out
