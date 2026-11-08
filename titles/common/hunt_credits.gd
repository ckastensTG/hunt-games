class_name HuntCredits
extends RefCounted
## What the hunt games add to the open-source notices (OpenSource): the
## fonts in ui/fonts/ (SIL Open Font License 1.1; the copyright lines from
## each font's OFL file there). The Credits screen also shows the title's
## author (TitleConfig).

const FONTS := [
	{"id": "alegreya", "name": "Alegreya and Alegreya SC (fonts)",
		"copyright": ["Copyright 2011 The Alegreya Project Authors (https://github.com/huertatipografica/Alegreya)"],
		"license": "OFL-1.1"},
	{"id": "alegreya_sans", "name": "Alegreya Sans (font)",
		"copyright": ["Copyright 2013 The Alegreya Sans Project Authors (https://github.com/huertatipografica/Alegreya-Sans)"],
		"license": "OFL-1.1"},
	{"id": "noto_sans_cjk", "name": "Noto Sans SC, TC, JP and KR (fonts)",
		"copyright": ["Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'"],
		"license": "OFL-1.1"},
	{"id": "noto_sans_thai", "name": "Noto Sans Thai (font)",
		"copyright": ["Copyright 2022 The Noto Project Authors (https://github.com/notofonts/thai)"],
		"license": "OFL-1.1"},
	{"id": "noto_sans_devanagari", "name": "Noto Sans Devanagari (font)",
		"copyright": ["Copyright 2022 The Noto Project Authors (https://github.com/notofonts/devanagari)"],
		"license": "OFL-1.1"},
]


static func entries() -> Array:
	return FONTS.duplicate(true)
