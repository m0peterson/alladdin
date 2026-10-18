extends SceneTree

# Run with a real renderer, after check.sh. Captures the actual main viewport.
const Player = preload("res://scripts/player.gd")
const CAPTURE_DIR: String = "res://.godot/t02-review"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("BLOCKED: capture needs a real renderer")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(CAPTURE_DIR) != OK:
		push_error("FAIL: cannot create capture directory")
		quit(1)
		return
	if change_scene_to_file("res://tests/fixtures/movement_arena.tscn") != OK:
		quit(1)
		return
	await scene_changed
	var player: Player = current_scene.get_node("World/Player") as Player
	await _save("arena")
	for direction: String in ["down", "left", "right", "up"]:
		player.position = Vector2(120, 124)
		await physics_frame
		Input.action_press("move_" + direction)
		var seen: Dictionary = {}
		for tick: int in range(50):
			await physics_frame
			await process_frame
			var frame: int = player.sprite.frame
			if player.sprite.animation == StringName("walk_" + direction) and not seen.has(frame):
				await _save("walk_%s_%d" % [direction, frame])
				seen[frame] = true
			if seen.size() == 4:
				break
		Input.action_release("move_" + direction)
		if seen.size() != 4:
			push_error("FAIL: incomplete walking cycle: " + direction)
			quit(1)
			return
		await physics_frame
		await process_frame
		await _save("idle_" + direction)
	player.position = Vector2(120, 124)
	Input.action_press("move_up")
	for tick: int in range(90):
		await physics_frame
		await process_frame
	Input.action_release("move_up")
	await physics_frame
	await process_frame
	await _save("north_edge")
	print("PASS: T02 renderer captures in .godot/t02-review")
	quit(0)


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(CAPTURE_DIR + "/" + label + ".png")
	if result != OK:
		push_error("FAIL: cannot save " + label)
		quit(1)
