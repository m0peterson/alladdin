extends SceneTree

const Player = preload("res://scripts/player.gd")
const ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]
const SPAWN: Vector2 = Vector2(136, 368)
const TOLERANCE: float = 1.3

var player: Player
var world: Node2D
var failures: int = 0
var visited_zones: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if change_scene_to_file("res://scenes/start.tscn") != OK:
		push_error("FAIL: cannot open the bazaar")
		quit(1)
		return
	await scene_changed
	world = current_scene.get_node("World") as Node2D
	player = world.get_node("Player") as Player
	await _frames(2)
	_check_scene_contract()
	_expect(player.position.distance_to(SPAWN) < TOLERANCE, "map starts beside the fence")
	await _check_routes()
	await _check_obstacles()
	_release()
	if failures:
		push_error("FAIL: T03 bazaar (%d assertions)" % failures)
		quit(1)
	else:
		print("PASS: T03 bazaar routes, zones, walls, NPC collisions and foot anchors")
		print("NOT RUN: visual Y sorting; inspect the actual renderer separately")
		quit(0)


func _check_scene_contract() -> void:
	_expect(world.y_sort_enabled, "world sorts bodies by their foot Y")
	var feet: CollisionShape2D = player.get_node("CollisionShape2D") as CollisionShape2D
	var shape: RectangleShape2D = feet.shape as RectangleShape2D
	_expect(shape != null, "player has a rectangular foot collider")
	if shape != null:
		_expect(is_zero_approx(feet.position.y + shape.size.y / 2.0), "player collider ends at foot origin")
	_expect(player.sprite.position == Vector2(0, -12), "player sprite ends at foot origin")
	for child: Node in world.get_children():
		if child is StaticBody2D:
			var body: StaticBody2D = child as StaticBody2D
			_expect(body.z_index == player.z_index, "shared Y-sort plane: " + body.name)
			var collision: CollisionShape2D = body.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if collision != null and collision.shape is RectangleShape2D:
				var body_shape: RectangleShape2D = collision.shape as RectangleShape2D
				_expect(is_zero_approx(collision.position.y + body_shape.size.y / 2.0), "body collider ends at foot origin: " + body.name)
	var ids: Dictionary = {}
	for zone_name: String in ["Market", "Warehouse", "Alley", "Fence", "Combat"]:
		var marker: Marker2D = current_scene.get_node_or_null("Regions/" + zone_name) as Marker2D
		_expect(marker != null, "zone marker exists: " + zone_name)
		if marker == null:
			continue
		var id: Variant = marker.get_meta("zone_id", null)
		_expect(id is String and not String(id).is_empty(), "stable zone ID: " + zone_name)
		_expect(not ids.has(id), "unique zone ID: " + zone_name)
		ids[id] = true


func _check_routes() -> void:
	# Input drives the real player continuously between waypoints. Teleporting is
	# limited to the beginning of each independent case.
	await _reset(SPAWN)
	_visit_zone("Fence")
	await _route("main warehouse door", [
		Vector2(240, 368), Vector2(240, 312), Vector2(504, 312), Vector2(504, 176),
	])
	_visit_zone("Warehouse")
	await _reset(SPAWN)
	await _route("alley warehouse door", [
		Vector2(48, 368), Vector2(48, 112), Vector2(208, 112),
		Vector2(208, 64), Vector2(376, 64), Vector2(376, 136),
	])
	_visit_zone("Alley")
	await _route("alley enters warehouse", [Vector2(456, 136), Vector2(504, 136), Vector2(504, 176)])
	_visit_zone("Warehouse")
	await _reset(SPAWN)
	await _route("market access", [Vector2(136, 296), Vector2(144, 296)])
	_visit_zone("Market")
	await _route("combat access", [Vector2(240, 296), Vector2(240, 344), Vector2(504, 344)])
	_visit_zone("Combat")
	await _route("return to the fence", [Vector2(504, 368), Vector2(136, 368)])
	_visit_zone("Fence")
	_expect(visited_zones.size() == 5, "all five zones reached through movement")
	print("INFO: two distinct warehouse entrances and all five zones reached without waypoint teleports")


func _route(label: String, points: Array[Vector2]) -> void:
	for point: Vector2 in points:
		if not await _move_to(point):
			_expect(false, "%s blocked before %s (at %s)" % [label, point, player.position])
			return


func _move_to(target: Vector2) -> bool:
	# Every segment has a finite budget, including when a route is obstructed.
	var budget: int = ceili((target - player.position).length() / Player.MOVE_SPEED * 60.0) + 30
	for tick: int in range(budget):
		var delta: Vector2 = target - player.position
		if absf(delta.x) <= TOLERANCE and absf(delta.y) <= TOLERANCE:
			_release()
			await _frames(1)
			return true
		var direction: Vector2 = Vector2(signf(delta.x), 0) if absf(delta.x) > TOLERANCE else Vector2(0, signf(delta.y))
		_set_direction(direction)
		await _frames(1)
	_release()
	return false


func _visit_zone(zone_name: String) -> void:
	var marker: Marker2D = current_scene.get_node_or_null("Regions/" + zone_name) as Marker2D
	if marker == null:
		return
	var reached: bool = player.global_position.distance_to(marker.global_position) <= TOLERANCE * 2.0
	_expect(reached, "walked to zone: " + zone_name)
	if reached:
		visited_zones[zone_name] = true


func _check_obstacles() -> void:
	# Representative tall wall and low counters: approach all four sides of the
	# actual collision geometry, rather than constructing a synthetic obstacle.
	await _check_wall_sides("Divider")
	await _check_wall_sides("StallWest", 104.0)
	await _check_wall_sides("FenceCounter", 104.0)
	for npc_name: String in ["MerchantWest", "MerchantEast", "Fence", "Bandit", "Guard"]:
		var npc: StaticBody2D = world.get_node(npc_name) as StaticBody2D
		await _push(npc.position - Vector2(24, 3), Vector2.RIGHT, 35)
		_expect(absf(player.position.x - (npc.position.x - 10.0)) < 0.2, "NPC blocks feet: " + npc_name)
		_expect(player.get_slide_collision_count() > 0, "NPC reports collision: " + npc_name)
	var slide_start: Vector2 = Vector2(244, 200)
	await _push(slide_start, Vector2(1, -1), 24)
	_expect(player.position.x <= 251.1 and player.position.y < slide_start.y - 10.0, "slides along divider without crossing it")
	await _push(Vector2(244, 278), Vector2(1, -1), 45)
	_expect(player.position.x <= 251.1 or player.position.y >= 269.9, "diagonal does not cross divider corner")
	await _push(Vector2(40, 72), Vector2(-1, -1), 120)
	_expect(absf(player.position.x - 21.0) < 0.2 and absf(player.position.y - 54.0) < 0.2, "north and west boundaries block feet")
	await _push(Vector2(608, 400), Vector2(1, 1), 90)
	_expect(absf(player.position.x - 619.0) < 0.2 and absf(player.position.y - 416.0) < 0.2, "south and east boundaries block feet")
	print("INFO: 12 wall sides, five NPCs, diagonal slide/corner and all four map boundaries checked")


func _check_wall_sides(wall_name: String, bottom_x: float = NAN) -> void:
	var wall: StaticBody2D = world.get_node(wall_name) as StaticBody2D
	var collider: CollisionShape2D = wall.get_node("CollisionShape2D") as CollisionShape2D
	var shape: RectangleShape2D = collider.shape as RectangleShape2D
	_expect(shape != null and not collider.disabled, "active rectangular wall: " + wall_name)
	if shape == null:
		return
	var rect: Rect2 = Rect2(collider.global_position - shape.size / 2.0, shape.size)
	var center: Vector2 = rect.get_center()
	await _push(Vector2(rect.position.x - 14.0, center.y), Vector2.RIGHT, 40)
	_expect(absf(player.position.x - (rect.position.x - 5.0)) < 0.2, wall_name + " blocks west")
	_expect(player.get_slide_collision_count() > 0, wall_name + " reports collision")
	await _push(Vector2(rect.end.x + 14.0, center.y), Vector2.LEFT, 40)
	_expect(absf(player.position.x - (rect.end.x + 5.0)) < 0.2, wall_name + " blocks east")
	await _push(Vector2(center.x, rect.position.y - 12.0), Vector2.DOWN, 40)
	_expect(absf(player.position.y - rect.position.y) < 0.2, wall_name + " blocks north")
	var lower_x: float = center.x if is_nan(bottom_x) else bottom_x
	await _push(Vector2(lower_x, rect.end.y + 18.0), Vector2.UP, 40)
	_expect(absf(player.position.y - (rect.end.y + 6.0)) < 0.2, wall_name + " blocks south")


func _push(start: Vector2, direction: Vector2, ticks: int) -> void:
	await _reset(start)
	_set_direction(direction)
	await _frames(ticks)


func _reset(start: Vector2) -> void:
	_release()
	player.position = start
	player.velocity = Vector2.ZERO
	await _frames(2)


func _set_direction(direction: Vector2) -> void:
	_release()
	if direction.x < 0:
		Input.action_press(&"move_left")
	elif direction.x > 0:
		Input.action_press(&"move_right")
	if direction.y < 0:
		Input.action_press(&"move_up")
	elif direction.y > 0:
		Input.action_press(&"move_down")


func _release() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
