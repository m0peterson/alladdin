extends SceneTree

const CAPTURE_DIR: String = "res://.godot/t03-review"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("BLOCKED: T03 capture needs a real renderer")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(CAPTURE_DIR) != OK:
		quit(1)
		return
	if change_scene_to_file("res://scenes/start.tscn") != OK:
		quit(1)
		return
	await scene_changed
	var player: CharacterBody2D = current_scene.get_node("World/Player") as CharacterBody2D
	player.set_physics_process(false)
	var views: Dictionary[String, Vector2] = {
		"start": Vector2(136, 368),
		"market": Vector2(144, 240),
		"alley": Vector2(376, 136),
		"warehouse": Vector2(504, 176),
		"combat": Vector2(504, 344),
		"stall_behind": Vector2(88, 174),
		"stall_front": Vector2(88, 199),
		"wall_behind": Vector2(472, 190),
		"wall_front": Vector2(472, 215),
	}
	for label: String in views:
		player.position = views[label]
		await process_frame
		await process_frame
		if not await _save(label):
			quit(1)
			return
	# Only the overview enlarges the capture viewport, with the same 1:1 pixels.
	# The five zone views above use the normal 320x180 game viewport.
	root.content_scale_size = Vector2i(640, 432)
	root.size = Vector2i(640, 432)
	(current_scene.get_node("Overlay") as CanvasLayer).hide()
	(player.get_node("Camera2D") as Camera2D).enabled = false
	var overview: Camera2D = Camera2D.new()
	overview.position = Vector2(320, 216)
	current_scene.add_child(overview)
	overview.make_current()
	await process_frame
	await process_frame
	if not await _save("overview"):
		quit(1)
		return
	print("PASS: T03 renderer captures in .godot/t03-review")
	quit(0)


func _save(label: String) -> bool:
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(CAPTURE_DIR + "/" + label + ".png") != OK:
		push_error("FAIL: cannot save " + label)
		return false
	return true
