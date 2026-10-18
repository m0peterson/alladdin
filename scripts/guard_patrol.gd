class_name GuardPatrol
extends CharacterBody2D

const Sight = preload("res://scripts/visibility_query.gd")

@export var guard_id: StringName
@export var route: PackedVector2Array
@export var patrol_speed: float = 28.0
@export var visibility: Sight = Sight.new()

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


func _physics_process(delta: float) -> void:
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
