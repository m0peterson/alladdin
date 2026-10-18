extends CharacterBody2D

const MOVE_SPEED: float = 72.0

# Kept when input stops; vertical input wins ties on a diagonal.
var facing: Vector2 = Vector2.DOWN

@onready var sprite: AnimatedSprite2D = $Sprite


func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if not direction.is_zero_approx():
		if absf(direction.x) > absf(direction.y):
			facing = Vector2(signf(direction.x), 0.0)
		else:
			facing = Vector2(0.0, signf(direction.y))
	velocity = direction * MOVE_SPEED
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
