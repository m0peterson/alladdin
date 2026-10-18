extends CharacterBody2D

signal defeated

const MOVE_SPEED: float = 72.0
const SNEAK_SPEED: float = 32.0
const ATTACK_DAMAGE: int = 20
const ATTACK_REACH: float = 26.0
const ATTACK_WINDUP: float = 0.10
const ATTACK_ACTIVE: float = 0.10
const ATTACK_RECOVERY: float = 0.20
const DODGE_SPEED: float = 210.0
const DODGE_DURATION: float = 0.18
const DODGE_COOLDOWN: float = 0.65
const HURT_INVULNERABILITY: float = 0.35

enum AttackPhase { IDLE, WINDUP, ACTIVE, RECOVERY }

# Kept when input stops; vertical input wins ties on a diagonal.
var facing: Vector2 = Vector2.DOWN
var state: PlayerState
var attack_phase: AttackPhase = AttackPhase.IDLE
var dodge_remaining: float = 0.0
var dodge_cooldown: float = 0.0
var _waiting_for_release: bool = false
var _sneak_waiting_for_release: bool = false
var _combat_waiting_for_release: bool = false
var _attack_requested: bool = false
var _dodge_requested: bool = false
var _phase_remaining: float = 0.0
var _attack_direction: Vector2 = Vector2.DOWN
var _dodge_direction: Vector2 = Vector2.DOWN
var _hit_targets: Dictionary = {}
var _hurt_remaining: float = 0.0
var _defeated: bool = false

@onready var sprite: AnimatedSprite2D = $Sprite


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or get_viewport().gui_get_focus_owner() != null or _combat_waiting_for_release or _defeated or event.is_echo():
		return
	if InputMap.has_action("attack") and event.is_action_pressed("attack"):
		_attack_requested = true
	if InputMap.has_action("dodge") and event.is_action_pressed("dodge"):
		_dodge_requested = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		suppress_combat_until_release()


func _physics_process(delta: float) -> void:
	if _sneak_waiting_for_release:
		_sneak_waiting_for_release = _combat_pressed("sneak")
	if _combat_waiting_for_release:
		_combat_waiting_for_release = _combat_pressed("attack") or _combat_pressed("dodge")
		_attack_requested = false
		_dodge_requested = false
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _waiting_for_release:
		_waiting_for_release = Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right") or Input.is_action_pressed("move_up") or Input.is_action_pressed("move_down")
		direction = Vector2.ZERO
	if _defeated:
		direction = Vector2.ZERO
	if attack_phase == AttackPhase.IDLE and dodge_remaining <= 0.0 and not direction.is_zero_approx():
		if absf(direction.x) > absf(direction.y):
			facing = Vector2(signf(direction.x), 0.0)
		else:
			facing = Vector2(0.0, signf(direction.y))
	_hurt_remaining = maxf(0.0, _hurt_remaining - delta)
	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)
	if not _defeated and _dodge_requested and dodge_cooldown <= 0.0 and attack_phase == AttackPhase.IDLE:
		dodge_remaining = DODGE_DURATION
		dodge_cooldown = DODGE_COOLDOWN
		_dodge_direction = direction.normalized() if not direction.is_zero_approx() else facing
	if not _defeated and _attack_requested and attack_phase == AttackPhase.IDLE and dodge_remaining <= 0.0:
		attack_phase = AttackPhase.WINDUP
		_phase_remaining = ATTACK_WINDUP
		_attack_direction = facing
		_hit_targets.clear()
	_attack_requested = false
	_dodge_requested = false
	if attack_phase != AttackPhase.IDLE:
		_phase_remaining -= delta
		if _phase_remaining <= 0.0:
			if attack_phase == AttackPhase.WINDUP:
				attack_phase = AttackPhase.ACTIVE
				_phase_remaining += ATTACK_ACTIVE
			elif attack_phase == AttackPhase.ACTIVE:
				attack_phase = AttackPhase.RECOVERY
				_phase_remaining += ATTACK_RECOVERY
			else:
				attack_phase = AttackPhase.IDLE
		if attack_phase == AttackPhase.ACTIVE:
			_hit_in_front()
	velocity = direction * (SNEAK_SPEED if is_sneaking() else MOVE_SPEED) if attack_phase == AttackPhase.IDLE else Vector2.ZERO
	if dodge_remaining > 0.0:
		velocity = _dodge_direction * DODGE_SPEED
		dodge_remaining = maxf(0.0, dodge_remaining - delta)
	move_and_slide()
	var moving: bool = get_position_delta().length_squared() > 0.001
	var direction_name: String = "down"
	if facing == Vector2.UP:
		direction_name = "up"
	elif facing == Vector2.LEFT:
		direction_name = "left"
	elif facing == Vector2.RIGHT:
		direction_name = "right"
	sprite.play(("walk_" if moving else "idle_") + direction_name)
	sprite.modulate = Color(1.0, 0.35, 0.3) if _hurt_remaining > 0.0 else (Color(0.5, 0.9, 1.0) if dodge_remaining > 0.0 else Color.WHITE)
	queue_redraw()


func is_sneaking() -> bool:
	return not _sneak_waiting_for_release and InputMap.has_action("sneak") and Input.is_action_pressed("sneak") and dodge_remaining <= 0.0


# Footsteps only: a simple radius, reduced by Shift. Guards additionally
# require an unobstructed ray; attacks and complex acoustic propagation are out of scope.
func get_noise_radius() -> float:
	if get_tree().paused or _defeated or velocity.length_squared() < 1.0 or get_position_delta().length_squared() < 0.001:
		return 0.0
	return 12.0 if is_sneaking() else 42.0


func _hit_in_front() -> void:
	for node: Node in get_tree().get_nodes_in_group("damageable"):
		if node == self or not node is Node2D or not node.has_method("receive_damage") or _hit_targets.has(node.get_instance_id()):
			continue
		var target: Node2D = node as Node2D
		if not target.is_visible_in_tree():
			continue
		var offset: Vector2 = target.global_position - global_position
		if offset.length() > ATTACK_REACH or (not offset.is_zero_approx() and offset.normalized().dot(_attack_direction) < 0.45):
			continue
		var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -3), target.global_position + Vector2(0, -3), 1, [get_rid()])
		if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		# Mark even rejected hits: invulnerability cannot turn repeated overlap into damage.
		_hit_targets[target.get_instance_id()] = true
		target.call("receive_damage", ATTACK_DAMAGE, global_position)


func receive_damage(amount: int, _origin: Vector2 = Vector2.ZERO) -> bool:
	if amount <= 0 or state == null or state.health <= 0 or _defeated or get_tree().paused or dodge_remaining > 0.0 or _hurt_remaining > 0.0:
		return false
	_hurt_remaining = HURT_INVULNERABILITY
	state.health -= amount
	if state.health == 0:
		_defeated = true
		attack_phase = AttackPhase.IDLE
		velocity = Vector2.ZERO
		defeated.emit()
	return true


func reset_combat() -> void:
	attack_phase = AttackPhase.IDLE
	_phase_remaining = 0.0
	dodge_remaining = 0.0
	dodge_cooldown = 0.0
	_hurt_remaining = 0.0
	_defeated = false
	_hit_targets.clear()
	suppress_combat_until_release()
	velocity = Vector2.ZERO
	if is_instance_valid(sprite):
		sprite.modulate = Color.WHITE
	queue_redraw()


func suppress_combat_until_release() -> void:
	_sneak_waiting_for_release = _combat_pressed("sneak")
	_combat_waiting_for_release = true
	_attack_requested = false
	_dodge_requested = false
	# A menu interrupts a pending swing rather than dealing damage on return.
	attack_phase = AttackPhase.IDLE
	dodge_remaining = 0.0
	velocity = Vector2.ZERO
	queue_redraw()


func suppress_movement_until_release() -> void:
	_sneak_waiting_for_release = _combat_pressed("sneak")
	_waiting_for_release = true
	velocity = Vector2.ZERO


func _combat_pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func _draw() -> void:
	if attack_phase != AttackPhase.IDLE:
		var center: Vector2 = Vector2(0, -8)
		var angle: float = _attack_direction.angle()
		var active: bool = attack_phase == AttackPhase.ACTIVE
		var color: Color = Color("fff0a0") if active else Color("a98e63")
		draw_arc(center, 20.0 if active else 14.0, angle - 0.9, angle + 0.9, 9, color, 3.0 if active else 1.0)
	elif dodge_remaining > 0.0:
		draw_line(Vector2(0, -7), Vector2(0, -7) - _dodge_direction * 14.0, Color("80dfff"), 3.0)
