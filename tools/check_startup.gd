extends SceneTree


func _initialize() -> void:
	var expected: Dictionary = {
		"application/run/main_scene": "res://scenes/start.tscn",
		"display/window/size/viewport_width": 320,
		"display/window/size/viewport_height": 180,
		"display/window/stretch/mode": "viewport",
		"display/window/stretch/scale_mode": "integer",
		"rendering/renderer/rendering_method": "gl_compatibility",
		"rendering/textures/canvas_textures/default_texture_filter": 0,
	}
	for setting: String in expected:
		if ProjectSettings.get_setting(setting) != expected[setting]:
			push_error("Unexpected project setting: " + setting)
			quit(1)
			return
	call_deferred("_load_scene")


func _load_scene() -> void:
	var result: Error = change_scene_to_file("res://scenes/start.tscn")
	if result != OK:
		push_error("Cannot load the startup scene")
		quit(1)
		return
	await scene_changed
	_check_scene()


func _check_scene() -> void:
	if not current_scene is Control or not current_scene.is_node_ready():
		push_error("Startup scene is not ready")
		quit(1)
		return
	var title: Label = current_scene.get_node_or_null("Overlay/Title") as Label
	if title == null or title.text != "Аладдин: Тени Аграбы":
		push_error("Startup title is missing")
		quit(1)
		return
	if root.content_scale_size != Vector2i(320, 180):
		push_error("Unexpected viewport dimensions")
		quit(1)
		return
	if root.content_scale_mode != Window.CONTENT_SCALE_MODE_VIEWPORT or root.content_scale_stretch != Window.CONTENT_SCALE_STRETCH_INTEGER:
		push_error("Integer viewport scaling is not active")
		quit(1)
		return
	if root.canvas_item_default_texture_filter != Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST:
		push_error("Nearest filtering is not active")
		quit(1)
		return
	print("PASS: T01 startup and settings")
	quit(0)
