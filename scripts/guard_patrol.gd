class_name GuardPatrol
extends CharacterBody2D

const Sight = preload("res://scripts/visibility_query.gd")

@export var guard_id: StringName
@export var route: PackedVector2Array
@export var patrol_speed: float = 28.0
@export var visibility: Sight = Sight.new()

enum State { PATROL, SUSPICIOUS, CHASE, SEARCH, RETURN }

const SUSPICION_TIME: float = 0.8
const CHASE_SPEED: float = 48.0
const INVESTIGATE_LIMIT: float = 3.0
const SEARCH_DURATION: float = 2.5

var state: State = State.PATROL
var suspicion: float = 0.0
var last_known_position: Vector2 = Vector2.ZERO
var _player: Node2D
var _state_time: float = 0.0
var _trail: Array[Vector2] = []
var _return_stalled: float = 0.0
var facing: Vector2 = Vector2.RIGHT
var waypoint_index: int = 1
var completed_loops: int = 0
var reached_waypoints: int = 0
var _walk_time: float = 0.0


static func install(world: Node2D) -> Array[GuardPatrol]:
	var guards: Array[GuardPatrol] = []
	var definitions: Dictionary = {
		&"guard_market": PackedVector2Array([Vector2(128, 144), Vector2(224, 144), Vector2(224, 224), Vector2(128, 224)]),
		&"guard_alley": PackedVector2Array([Vector2(352, 64), Vector2(392, 64), Vector2(392, 160), Vector2(352, 160)]),
		&"guard_warehouse": PackedVector2Array([Vector2(456, 128), Vector2(560, 128), Vector2(560, 184), Vector2(456, 184)]),
	}
	for stable_id: StringName in definitions:
		var guard: GuardPatrol = world.get_node_or_null(NodePath(stable_id)) as GuardPatrol
		if guard == null:
			guard = GuardPatrol.new()
			guard.name = stable_id
			guard.guard_id = stable_id
			guard.route = definitions[stable_id]
			guard.position = guard.route[0]
			world.add_child(guard)
		guards.append(guard)
	return guards


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = 1
	collision_mask = 3
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	set_meta("world_id", String(guard_id))
	add_to_group("guards")
	var feet: CollisionShape2D = CollisionShape2D.new()
	feet.name = "CollisionShape2D"
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(10, 6)
	feet.shape = shape
	feet.position = Vector2(0, -3)
	add_child(feet)


func configure(player: Node2D) -> void:
	_player = player


# Only this snapshot is evidence; a report never enables hidden tracking.
func report_crime(known_position: Vector2) -> void:
	if state == State.PATROL:
		_trail = [global_position]
	last_known_position = known_position
	suspicion = 1.0
	_set_state(State.CHASE)


func _set_state(next: State) -> void:
	state = next
	_state_time = 0.0
	_return_stalled = 0.0


func _physics_process(delta: float) -> void:
	if is_instance_valid(_player) or state != State.PATROL:
		_update_detection(delta)
	if state != State.PATROL:
		_update_alert_movement(delta)
		queue_redraw()
		return
	_patrol(delta)


func _update_detection(delta: float) -> void:
	_state_time += delta
	var excluded: Array[RID] = []
	if is_instance_valid(_player) and _player is CollisionObject2D:
		excluded.append((_player as CollisionObject2D).get_rid())
	var sees_player: bool = is_instance_valid(_player) and can_see(_player.global_position, excluded)
	if sees_player:
		last_known_position = _player.global_position
		if state == State.PATROL:
			_trail = [global_position]
			_set_state(State.SUSPICIOUS)
		if state == State.SUSPICIOUS:
			suspicion = minf(1.0, suspicion + delta / SUSPICION_TIME)
			if suspicion >= 1.0:
				_set_state(State.CHASE)
		elif state != State.CHASE:
			suspicion = 1.0
			_set_state(State.CHASE)
		else:
			# Only fresh sight renews the pursuit deadline.
			_state_time = 0.0
	elif state == State.PATROL and _hears_player():
		_trail = [global_position]
		last_known_position = _player.global_position
		suspicion = 0.3
		_set_state(State.SUSPICIOUS)
	elif state == State.SUSPICIOUS:
		suspicion = maxf(0.0, suspicion - delta * 0.35)
		if suspicion <= 0.0:
			_set_state(State.RETURN)
	elif state == State.CHASE and (global_position.distance_to(last_known_position) < 5.0 or _state_time >= INVESTIGATE_LIMIT):
		_set_state(State.SEARCH)
	elif state == State.SEARCH and _state_time >= SEARCH_DURATION:
		suspicion = 0.0
		_set_state(State.RETURN)


func _hears_player() -> bool:
	if not is_instance_valid(_player) or not _player.has_method("get_noise_radius"):
		return false
	var radius: float = float(_player.call("get_noise_radius"))
	if radius <= 0.0 or global_position.distance_to(_player.global_position) > radius:
		return false
	var excluded: Array[RID] = [get_rid()]
	if _player is CollisionObject2D:
		excluded.append((_player as CollisionObject2D).get_rid())
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, _player.global_position, visibility.occluder_mask, excluded)
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _update_alert_movement(delta: float) -> void:
	velocity = Vector2.ZERO
	if state == State.SEARCH:
		facing = Vector2.RIGHT.rotated(_state_time * TAU / SEARCH_DURATION)
	elif state == State.CHASE:
		_move_toward(last_known_position, CHASE_SPEED, delta)
		if _trail.is_empty() or _trail.back().distance_to(global_position) >= 6.0:
			_trail.append(global_position)
	elif state == State.SUSPICIOUS:
		facing = global_position.direction_to(last_known_position)
	elif state == State.RETURN:
		while not _trail.is_empty() and global_position.distance_to(_trail.back()) < 2.0:
			_trail.pop_back()
		if _trail.is_empty():
			_set_state(State.PATROL)
		else:
			_move_toward(_trail.back(), patrol_speed, delta)
			# A dynamic obstruction may temporarily block the recorded walkable
			# trail. Stay in RETURN and retry: no endless alarm or wall teleport.
			_return_stalled = _return_stalled + delta if get_position_delta().length_squared() < 0.001 else 0.0
			if _return_stalled >= 1.0:
				facing = -facing
				_return_stalled = 0.0
	if get_position_delta().length_squared() > 0.001:
		_walk_time += delta


func _move_toward(destination: Vector2, speed: float, delta: float) -> void:
	var offset: Vector2 = destination - global_position
	if offset.is_zero_approx():
		return
	facing = offset.normalized()
	velocity = facing * minf(speed, offset.length() / delta)
	move_and_slide()


func _patrol(delta: float) -> void:
	if route.size() < 2 or patrol_speed <= 0.0:
		velocity = Vector2.ZERO
		return
	var offset: Vector2 = route[waypoint_index] - position
	if offset.length() < 0.1:
		reached_waypoints += 1
		if waypoint_index == 0:
			completed_loops += 1
		waypoint_index = (waypoint_index + 1) % route.size()
		offset = route[waypoint_index] - position
	facing = offset.normalized()
	velocity = facing * minf(patrol_speed, offset.length() / delta)
	move_and_slide()
	if get_position_delta().length_squared() > 0.001:
		_walk_time += delta
	queue_redraw()


func can_see(target_position: Vector2, excluded: Array[RID] = []) -> bool:
	return visibility.can_see(self, target_position, facing, excluded)


func _draw() -> void:
	CharacterVisual.draw_actor(self, "guard", facing, velocity.length_squared() > 0.01, _walk_time)
	CharacterVisual.draw_guard_state(self, state)


func save_snapshot() -> Dictionary:
	var trail: Array = []
	for point: Vector2 in _trail:
		trail.append({"x": point.x, "y": point.y})
	return {"position": {"x": position.x, "y": position.y},
		"facing": {"x": facing.x, "y": facing.y}, "state": state, "suspicion": suspicion,
		"last_known_position": {"x": last_known_position.x, "y": last_known_position.y},
		"state_time": _state_time, "trail": trail, "return_stalled": _return_stalled,
		"waypoint_index": waypoint_index}


static func valid_point(data: Variant, direction: bool = false) -> bool:
	if data is not Dictionary:
		return false
	for axis: String in ["x", "y"]:
		var value: Variant = data.get(axis)
		if (value is not int and value is not float) or not is_finite(float(value)):
			return false
		if value < (-1 if direction else 0) or value > (1 if direction else (640 if axis == "x" else 432)):
			return false
	return true


func validate_snapshot(data: Variant) -> String:
	if data is not Dictionary or not PlayerSave.integer_in(data.get("state"), State.PATROL, State.RETURN) or not PlayerSave.integer_in(data.get("waypoint_index"), 0, route.size() - 1):
		return "Неверное состояние стражника."
	for key: String in ["position", "last_known_position", "facing"]:
		if not valid_point(data.get(key), key == "facing"):
			return "Неверное положение стражника."
	for key: String in ["suspicion", "state_time", "return_stalled"]:
		var value: Variant = data.get(key)
		if (value is not int and value is not float) or not is_finite(float(value)) or value < 0 or value > (1.0 if key == "suspicion" else 1000000000.0):
			return "Неверный таймер тревоги."
	# Do not silently truncate: every point is needed for obstacle-safe return.
	# Long uninterrupted chases exceeding this bound must end before saving.
	if data.get("trail") is not Array or data["trail"].size() > 4096:
		return "Путь возврата стражника слишком длинный. Завершите погоню перед сохранением."
	for point: Variant in data["trail"]:
		if not valid_point(point):
			return "Неверный путь возврата стражника."
	return ""


func restore_snapshot(data: Variant) -> bool:
	if not validate_snapshot(data).is_empty():
		return false
	position = Vector2(data["position"]["x"], data["position"]["y"])
	facing = Vector2(data["facing"]["x"], data["facing"]["y"])
	last_known_position = Vector2(data["last_known_position"]["x"], data["last_known_position"]["y"])
	state = int(data["state"]) as State
	suspicion = float(data["suspicion"])
	_state_time = float(data["state_time"])
	_return_stalled = float(data["return_stalled"])
	waypoint_index = int(data["waypoint_index"])
	_trail.clear()
	for point: Dictionary in data["trail"]:
		_trail.append(Vector2(point["x"], point["y"]))
	velocity = Vector2.ZERO
	queue_redraw()
	return true
