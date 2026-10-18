extends SceneTree

const Player = preload("res://scripts/player.gd")
const ALL_KEYS: Array[Key] = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]
const OPEN_START: Vector2 = Vector2(120, 124)

var player: Player
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if change_scene_to_file("res://tests/fixtures/movement_arena.tscn") != OK:
		push_error("FAIL: cannot open the movement arena")
		quit(1)
		return
	await scene_changed
	player = current_scene.get_node("World/Player") as Player
	await _frames(2)
	var directions: Array[Vector2] = [Vector2.UP, Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT]
	var names: Array[String] = ["up", "left", "down", "right"]
	var letters: Array[Key] = [KEY_W, KEY_A, KEY_S, KEY_D]
	var arrows: Array[Key] = [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]
	var straight_distance: float = 0.0
	for index: int in range(4):
		var displacement: Vector2 = await _walk(OPEN_START, [letters[index]], 12)
		_expect(displacement.dot(directions[index]) > 13.0, "WASD moves " + names[index])
		_expect(displacement.is_equal_approx(directions[index] * displacement.length()), "WASD axis " + names[index])
		_expect(player.facing == directions[index], "facing " + names[index])
		_expect(player.sprite.animation == StringName("walk_" + names[index]), "walking " + names[index])
		straight_distance = displacement.length()
		_release()
		var stop: Vector2 = player.position
		await _frames(3)
		_expect(player.position.is_equal_approx(stop), "release stops " + names[index])
		_expect(player.facing == directions[index], "idle retains facing " + names[index])
		_expect(player.sprite.animation == StringName("idle_" + names[index]), "idle " + names[index])
		var arrow_displacement: Vector2 = await _walk(OPEN_START, [arrows[index]], 12)
		_expect(arrow_displacement.is_equal_approx(displacement), "arrow matches WASD " + names[index])
	print("INFO: straight distance over 12 ticks = ", straight_distance)
	for horizontal: Key in [KEY_A, KEY_D]:
		for vertical: Key in [KEY_W, KEY_S]:
			var diagonal: Vector2 = await _walk(OPEN_START, [horizontal, vertical], 12)
			_expect(absf(diagonal.length() - straight_distance) < 0.05, "diagonal has equal speed")
			_expect(absf(absf(diagonal.x) - absf(diagonal.y)) < 0.01, "diagonal axes match")
			_expect(player.facing == (Vector2.UP if vertical == KEY_W else Vector2.DOWN), "vertical wins diagonal tie")
	var duplicate: Vector2 = await _walk(OPEN_START, [KEY_W, KEY_UP], 12)
	_expect(absf(duplicate.length() - straight_distance) < 0.05, "same direction on two keys does not accelerate")
	var opposed: Vector2 = await _walk(OPEN_START, [KEY_A, KEY_D, KEY_W, KEY_S], 12)
	_expect(opposed.is_zero_approx(), "opposite inputs cancel")
	print("PASS: keyboard input, speed, facing and idle/walk" if failures == 0 else "FAIL: keyboard input")
	await _check_walls()
	_check_frames()
	_release()
	if failures:
		push_error("FAIL: T02 movement (%d assertions)" % failures)
		quit(1)
	else:
		print("PASS: T02 movement, collisions, facing and sprite foot baseline")
		quit(0)


func _check_walls() -> void:
	# Approach every side of every actual wall, not a synthetic test collider.
	for wall_name: String in ["WestWall", "NorthWall", "EastWall"]:
		var wall: StaticBody2D = current_scene.get_node("World/" + wall_name) as StaticBody2D
		var center: Vector2 = wall.position - Vector2(0, 16)
		await _walk(center - Vector2(32, 0), [KEY_D], 40)
		_expect(player.position.x <= center.x - 21.0 + 0.1, wall_name + " blocks left side")
		_expect(player.get_slide_collision_count() > 0, wall_name + " reports collision")
		_expect(player.sprite.animation == &"idle_right", "blocked movement idles")
		await _walk(center + Vector2(32, 0), [KEY_A], 40)
		_expect(player.position.x >= center.x + 21.0 - 0.1, wall_name + " blocks right side")
		await _walk(center - Vector2(0, 22), [KEY_S], 40)
		_expect(player.position.y <= center.y - 16.0 + 0.1, wall_name + " blocks top side")
		await _walk(center + Vector2(0, 28), [KEY_W], 40)
		_expect(player.position.y >= center.y + 22.0 - 0.1, wall_name + " blocks bottom side")
	# Slide along a side and meet its corner diagonally.
	var slide: Vector2 = await _walk(Vector2(102, 108), [KEY_A, KEY_W], 16)
	_expect(player.position.x >= 101.0 - 0.1 and slide.y < -10.0, "diagonal slides along wall")
	await _walk(Vector2(106, 122), [KEY_A, KEY_W], 28)
	_expect(player.position.x >= 101.0 - 0.1 or player.position.y >= 118.0 - 0.1, "diagonal cannot cross wall corner")
	await _walk(Vector2(40, 70), [KEY_A, KEY_W], 120)
	_expect(player.position.x >= 21.0 - 0.1 and player.position.y >= 50.0 - 0.1, "north/west bounds")
	_expect(player.position.y - 24.0 >= 20.0, "north bound keeps sprite clear of title")
	await _walk(Vector2(280, 140), [KEY_D, KEY_S], 120)
	_expect(player.position.x <= 299.0 + 0.1 and player.position.y <= 156.0 + 0.1, "south/east bounds")
	print("INFO: checked all 12 wall sides, diagonal slide/corner and four arena bounds")


func _check_frames() -> void:
	var animations: SpriteFrames = player.sprite.sprite_frames
	for direction: String in ["down", "left", "right", "up"]:
		for state: String in ["idle", "walk"]:
			var animation: StringName = StringName(state + "_" + direction)
			_expect(animations.has_animation(animation), "animation exists: " + animation)
			var different_frames: Dictionary = {}
			for index: int in range(animations.get_frame_count(animation)):
				var texture: Texture2D = animations.get_frame_texture(animation, index)
				var image: Image = texture.get_image()
				_expect(image.get_size() == Vector2i(16, 24), "frame dimensions")
				_expect(image.get_used_rect().end.y == 24, "foot baseline stays at y=23")
				different_frames[image.get_data().hex_encode()] = true
			if state == "walk":
				_expect(different_frames.size() >= 3, "walk contains distinct steps: " + direction)
	_expect(player.sprite.position == Vector2(0, -12), "sprite bottom matches body origin")
	var feet: CollisionShape2D = player.get_node("CollisionShape2D") as CollisionShape2D
	var shape: RectangleShape2D = feet.shape as RectangleShape2D
	_expect(is_zero_approx(feet.position.y + shape.size.y / 2.0), "collision feet share sprite baseline")
	print("INFO: eight animations checked; sprite and collider share the foot anchor")


func _walk(start: Vector2, keys: Array[Key], ticks: int) -> Vector2:
	_release()
	player.position = start
	player.velocity = Vector2.ZERO
	await _frames(2)
	for key: Key in keys:
		_key(key, true)
	await _frames(ticks)
	return player.position - start


func _frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _release() -> void:
	for key: Key in ALL_KEYS:
		_key(key, false)


func _key(key: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
