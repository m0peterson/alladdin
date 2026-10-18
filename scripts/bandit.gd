class_name BazaarBandit
extends CharacterBody2D

signal defeated

const MAX_HEALTH: int = 60
const SPEED: float = 38.0
const AGGRO_RANGE: float = 88.0
const LEASH_RANGE: float = 104.0
const ATTACK_RANGE: float = 24.0
const WINDUP_TIME: float = 0.55
const ACTIVE_TIME: float = 0.14
const RECOVERY_TIME: float = 0.65
const DAMAGE: int = 20

enum Phase { IDLE, APPROACH, WINDUP, ACTIVE, RECOVERY, DEFEATED }

var target: Node2D
var home: Vector2
var health: int = MAX_HEALTH
var phase: Phase = Phase.IDLE
var phase_time: float = 0.0
var facing: Vector2 = Vector2.LEFT
var hit_flash: float = 0.0
var _attack_connected: bool = false


# Add this node to World, then configure with the existing Player.
func configure(player: Node2D) -> void:
	target = player


func _ready() -> void:
	home = global_position
	collision_layer = 4
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("damageable")
	if get_node_or_null("Feet") == null:
		var feet: CollisionShape2D = CollisionShape2D.new()
		feet.name = "Feet"
		var shape: RectangleShape2D = RectangleShape2D.new()
		shape.size = Vector2(10, 6)
		feet.shape = shape
		feet.position = Vector2(0, -3)
		add_child(feet)


func _physics_process(delta: float) -> void:
	hit_flash = maxf(0.0, hit_flash - delta)
	velocity = Vector2.ZERO
	if phase == Phase.DEFEATED:
		queue_redraw()
		return
	if not is_instance_valid(target):
		queue_redraw()
		return
	var offset: Vector2 = target.global_position - global_position
	if phase == Phase.WINDUP or phase == Phase.ACTIVE or phase == Phase.RECOVERY:
		phase_time -= delta
		if phase == Phase.ACTIVE:
			_try_hit()
		if phase_time <= 0.0:
			if phase == Phase.WINDUP:
				phase = Phase.ACTIVE
				phase_time = ACTIVE_TIME
				_try_hit()
			elif phase == Phase.ACTIVE:
				phase = Phase.RECOVERY
				phase_time = RECOVERY_TIME
			else:
				phase = Phase.IDLE
	else:
		var within_duel: bool = target.global_position.distance_to(home) <= LEASH_RANGE
		if within_duel and offset.length() <= AGGRO_RANGE and _clear_path(target.global_position):
			facing = offset.normalized() if not offset.is_zero_approx() else facing
			if offset.length() <= ATTACK_RANGE:
				phase = Phase.WINDUP
				phase_time = WINDUP_TIME
				_attack_connected = false
			else:
				phase = Phase.APPROACH
				velocity = facing * SPEED
		else:
			phase = Phase.IDLE
			if global_position.distance_to(home) > 2.0 and _clear_path(home):
				velocity = global_position.direction_to(home) * SPEED
	move_and_slide()
	queue_redraw()


func _try_hit() -> void:
	if _attack_connected or not is_instance_valid(target):
		return
	var offset: Vector2 = target.global_position - global_position
	if offset.length() > ATTACK_RANGE + 3.0:
		return
	if not offset.is_zero_approx() and facing.dot(offset.normalized()) < 0.55:
		return
	if not _clear_path(target.global_position):
		return
	# One attempt per swing, including an evaded hit; no lingering damage.
	_attack_connected = true
	if target.has_method("receive_damage"):
		target.receive_damage(DAMAGE, global_position)


func _clear_path(destination: Vector2) -> bool:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, destination, 1)
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func receive_damage(amount: int, _origin: Vector2 = Vector2.ZERO) -> bool:
	if amount <= 0 or health <= 0 or get_tree().paused:
		return false
	health = maxi(0, health - amount)
	hit_flash = 0.18
	if health == 0:
		phase = Phase.DEFEATED
		velocity = Vector2.ZERO
		remove_from_group("damageable")
		defeated.emit()
	queue_redraw()
	return true


func reset_duel() -> void:
	# A won duel stays won for the current game.
	if health == 0:
		return
	global_position = home
	velocity = Vector2.ZERO
	health = MAX_HEALTH
	phase = Phase.IDLE
	phase_time = 0.0
	_attack_connected = false
	hit_flash = 0.0
	queue_redraw()


func _draw() -> void:
	if phase == Phase.DEFEATED:
		draw_rect(Rect2(-9, -4, 18, 4), Color("725047"))
		draw_rect(Rect2(7, -6, 2, 7), Color("c8bfb0"))
		return
	var tint: Color = Color.WHITE if hit_flash > 0.0 else Color("735047")
	draw_ellipse_shadow()
	if phase == Phase.WINDUP:
		draw_arc(Vector2(0, -3), ATTACK_RANGE, facing.angle() - 0.65, facing.angle() + 0.65, 12, Color("edac48"), 2.0)
		draw_rect(Rect2(-1, -30, 2, 5), Color("ffdb70"))
		draw_rect(Rect2(-1, -23, 2, 2), Color("ffdb70"))
	elif phase == Phase.ACTIVE:
		draw_arc(Vector2(0, -3), ATTACK_RANGE, facing.angle() - 0.65, facing.angle() + 0.65, 12, Color("fff0ba"), 3.0)
	draw_rect(Rect2(-5, -2, 4, 2), Color("402e34"))
	draw_rect(Rect2(1, -2, 4, 2), Color("402e34"))
	draw_rect(Rect2(-4, -13, 8, 11), tint)
	draw_rect(Rect2(-3, -20, 6, 7), Color.WHITE if hit_flash > 0.0 else Color("e0ae75"))
	draw_rect(Rect2(-4, -20, 8, 2), Color("b64b42"))
	var blade: Vector2 = facing * (10.0 if phase == Phase.WINDUP else 7.0)
	draw_line(blade + Vector2(0, -12), blade + Vector2(0, -3), Color("c8bfb0"), 2.0)
	draw_rect(Rect2(-8, -26, 16, 2), Color("402e34"))
	draw_rect(Rect2(-8, -26, 16.0 * health / MAX_HEALTH, 2), Color("d05c4d"))


func draw_ellipse_shadow() -> void:
	draw_rect(Rect2(-6, -2, 12, 3), Color(0.16, 0.10, 0.14, 0.45))
