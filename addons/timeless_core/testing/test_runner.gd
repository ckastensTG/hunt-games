extends SceneTree
## Headless test runner.
##
##   godot --headless --path <project> -s res://addons/timeless_core/testing/test_runner.gd \
##         -- --dir=res://tests --dir=res://addons/timeless_core/tests [--filter=name] [--include-slow]
##
## Runs every test_*.gd under the given directories. Test methods named
## test_slow_* are skipped unless --include-slow is passed.
## Exit code is the number of failed tests (capped at 255).

func _init() -> void:
	var dirs: Array[String] = []
	var filter := ""
	var include_slow := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dirs.append(arg.substr(6))
		elif arg.begins_with("--filter="):
			filter = arg.substr(9)
		elif arg == "--include-slow":
			include_slow = true
	if dirs.is_empty():
		dirs = ["res://tests"]
	var files: Array[String] = []
	for d in dirs:
		_collect(d, files)
	files.sort()
	var passed := 0
	var failed := 0
	var skipped := 0
	var t0 := Time.get_ticks_msec()
	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("ERROR  could not load %s" % path)
			failed += 1
			continue
		var inst: Object = script.new()
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (filter in name or filter in path):
				continue
			if name.begins_with("test_slow_") and not include_slow:
				skipped += 1
				continue
			var t := Time.get_ticks_msec()
			inst.call(name)
			var failures: Array[String] = inst.take_failures()
			var ms := Time.get_ticks_msec() - t
			if failures.is_empty():
				passed += 1
				print("ok     %s::%s (%d ms)" % [path.get_file(), name, ms])
			else:
				failed += 1
				print("FAIL   %s::%s (%d ms)" % [path.get_file(), name, ms])
				for f in failures:
					print("         - " + f)
	print("\n%d passed, %d failed, %d skipped in %.1f s" % [passed, failed, skipped, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(mini(failed, 255))


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		print("WARN   no test directory %s" % dir_path)
		return
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
