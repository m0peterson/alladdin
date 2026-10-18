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
	if _player is CollisionObject2D:
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
	var step: float = 1.0 if sin(_walk_time * 12.0) >= 0.0 else -1.0
	draw_rect(Rect2(-6, -2, 12, 3), Color(0.15, 0.11, 0.15, 0.3))
	draw_rect(Rect2(-5, -2 - step, 4, 2), Color("402e34"))
	draw_rect(Rect2(1, -2 + step, 4, 2), Color("402e34"))
	draw_rect(Rect2(-4, -13, 8, 11), Color("4a6ea3"))
	draw_rect(Rect2(-3, -20, 6, 7), Color("e0ae75"))
	draw_rect(Rect2(-4, -22, 8, 5), Color("b6c3c4"))
	draw_rect(Rect2(6, -25, 1, 24), Color("b6c3c4"))
	# A small visor follows the actual query heading.
	draw_rect(Rect2(Vector2(-1, -18) + facing * 2, Vector2(2, 2)), Color("31445b"))
