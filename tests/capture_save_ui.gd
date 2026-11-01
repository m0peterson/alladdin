extends SceneTree

# Optional real-renderer fixture; never uses the normal player save.
const SAVE_PATH: String = "res://.godot/save-ui-review.json"
var game: Variant
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("BLOCKED: save UI needs a real renderer")
		quit(1)
		return
	_cleanup()
	game = load("res://scenes/game.tscn").instantiate()
	game.saves = WorldSave.new(SAVE_PATH)
	root.add_child(game)
	await _frames(3)
	await _capture("main-menu")
	game._new_game()
	await _frames(3)
	game._save_player()
	_expect(game.save_panel.visible and game.saves.read_file().get("ok", false), "valid full save")
	await _capture("save-confirmation")
	game._close_save_panel()
	game._save_player()
	game._close_save_panel()
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	game._load_player()
	_expect(game.save_panel.visible and game.backup_button.visible, "explicit backup choice")
	await _capture("save-recovery")
	game._recover_backup()
	_expect(game.saves.read_file().get("ok", false), "valid recovered save")
	await _capture("save-restored")
	game._close_save_panel()
	game.clock.advance(360.0)
	await _frames(3)
	_expect(game.clock.day_index == 1, "next-day HUD")
	await _capture("day-hud")
	_cleanup()
	print("PASS: final save UI render" if failures == 0 else "FAIL: final save UI render")
	quit(0 if failures == 0 else 1)


func _frames(count: int) -> void:
	for tick: int in range(count):
		await process_frame
		await physics_frame


func _capture(label: String) -> void:
	await _frames(2)
	await RenderingServer.frame_post_draw
	_expect(root.get_texture().get_image().save_png("res://artifacts/t15-t19/" + label + ".png") == OK, "capture " + label)


func _expect(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(SAVE_PATH + suffix):
			DirAccess.remove_absolute(SAVE_PATH + suffix)
