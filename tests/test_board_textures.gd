extends TestCase
## Import settings for the looks' board, mat, rope and slab-side textures.
##
## All of them are VRAM compressed with "high quality" (ASTC 4x4 on phones,
## BPTC on desktop) and mipmapped (Christopher, 2026-11-06: ASTC for every
## look). ETC2 put stair-steps on the brass engraving; uncompressed brass
## took 73 MB of GPU memory. On the moto g(20) ASTC drew as fast as ETC2.
## Normal maps are imported as normal maps (two channels); the shaders
## rebuild z from x and y.

const ART_DIRS := [
	"res://titles/bagh_chal/art/board",
	"res://titles/bagh_chal/art/modern",
	"res://titles/bagh_chal/art/stone",
]


func test_board_textures_are_astc_with_mipmaps() -> void:
	var seen := 0
	for dir in ART_DIRS:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".png.import"):
				continue
			seen += 1
			var path: String = dir.path_join(file)
			var cfg := ConfigFile.new()
			check_eq(cfg.load(path), OK, "%s reads" % path)
			check_eq(int(cfg.get_value("params", "compress/mode", -1)), 2, "%s: VRAM compressed" % path)
			check_eq(bool(cfg.get_value("params", "compress/high_quality", false)), true,
				"%s: high quality (ASTC on phones)" % path)
			check_eq(bool(cfg.get_value("params", "mipmaps/generate", false)), true, "%s: mipmaps" % path)
			if file.contains("_normal"):
				check_eq(int(cfg.get_value("params", "compress/normal_map", 0)), 1, "%s: imported as a normal map" % path)
	check(seen >= 20, "found the board textures (%d)" % seen)
