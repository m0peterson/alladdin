extends SceneTree

var failures: int = 0
var capture: bool = false


func _initialize() -> void:
	capture = "--capture-review" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _run() -> void:
	for role: String in ["aladdin", "merchant", "fence", "guard", "bandit"]:
		var texture: Texture2D = load("res://assets/characters/" + role + ".png") as Texture2D
		var atlas: Image = texture.get_image()
		_expect(atlas.get_size() == Vector2i(48, 96), role + " atlas dimensions")
		var headings: Array[PackedByteArray] = []
		for direction: int in range(4):
			var heading: PackedByteArray = atlas.get_region(Rect2i(0, direction * 24, 16, 24)).get_data()
			_expect(not headings.has(heading), role + " distinct heading " + str(direction))
			headings.append(heading)
			for step: int in range(3):
				var support: bool = false
				for x: int in range(16):
					support = support or atlas.get_pixel(step * 16 + x, direction * 24 + 23).a > 0.0
				_expect(support, role + " support foot at bottom")
	if capture:
		if DisplayServer.get_name() == "headless":
			push_error("BLOCKED: visual captures require a renderer")
			quit(1)
			return
		await _capture()
	print("PASS: five atlases, distinct four headings, support feet in all 60 frames" if failures == 0 else "FAIL: visual resource contract")
	quit(1 if failures else 0)


func _capture() -> void:
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	var game = current_scene
	game._new_game()
	for frame: int in range(3):
		await process_frame
	game.player.set_physics_process(false)
	for child: Node in game.world.get_node("World").get_children():
		if child is GuardPatrol or child is BazaarBandit:
			child.set_physics_process(false)
	for label: String in ["stall-behind", "stall-front"]:
		game.player.position = Vector2(88, 174 if label == "stall-behind" else 199)
		for frame: int in range(3):
			await process_frame
		await _save(label)
	for direction: Vector2 in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
		game.player.facing = direction
		game.player._physics_process(0.0)
		await process_frame
		await _save("heading-" + str(int(direction.x)) + "-" + str(int(direction.y)))
	# Only the camera is staged; the actual guard advances through its AI.
	game.player.position = Vector2(136, 368)
	var guard: GuardPatrol = game.guards[0]
	var camera: Camera2D = game.player.get_node("Camera2D") as Camera2D
	camera.position = guard.global_position - game.player.global_position
	guard.set_physics_process(true)
	guard.report_crime(guard.global_position)
	await _save("guard-chase")
	for frame: int in range(8):
		await physics_frame
		await process_frame
	_expect(guard.state == GuardPatrol.State.SEARCH, "report without fresh sight leads to search")
	await _save("guard-search")
	for frame: int in range(180):
		await physics_frame
		await process_frame
	_expect(guard.state == GuardPatrol.State.PATROL and guard.suspicion == 0.0, "search ends and patrol resumes")
	await _save("guard-clear")


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/t18-review")
	_expect(root.get_texture().get_image().save_png("res://.godot/t18-review/" + label + ".png") == OK, "capture " + label)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
