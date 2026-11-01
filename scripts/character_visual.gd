class_name CharacterVisual
extends RefCounted

# Pure drawing: reads the actor's heading/state, never changes gameplay.
const ATLASES: Dictionary = {
	"merchant": preload("res://assets/characters/merchant.png"),
	"fence": preload("res://assets/characters/fence.png"),
	"guard": preload("res://assets/characters/guard.png"),
	"bandit": preload("res://assets/characters/bandit.png"),
}


static func draw_actor(canvas: CanvasItem, role: String, facing: Vector2 = Vector2.DOWN,
		moving: bool = false, clock: float = 0.0, flash: bool = false) -> void:
	var direction: int = 0
	if absf(facing.x) > absf(facing.y):
		direction = 2 if facing.x > 0.0 else 1
	elif facing.y < 0.0:
		direction = 3
	var step: int = 1 + (int(clock * 8.0) % 2) if moving else 0
	canvas.draw_rect(Rect2(-6, -2, 12, 2), Color(0.16, 0.10, 0.14, 0.35))
	canvas.draw_texture_rect_region(ATLASES[role], Rect2(-8, -24, 16, 24),
		Rect2(step * 16, direction * 24, 16, 24), Color(2, 2, 2) if flash else Color.WHITE)
	if role == "guard":
		canvas.draw_rect(Rect2(9, -24, 1, 23), Color("533746"))
		canvas.draw_rect(Rect2(8, -27, 3, 5), Color("dce0d0"))
		canvas.draw_rect(Rect2(8, -17, 2, 2), Color("d4973f"))
	elif role == "bandit":
		var blade: Vector2 = Vector2(roundf(facing.x * 8), -10 + roundf(facing.y * 4))
		canvas.draw_rect(Rect2(blade, Vector2(2, 8)), Color("dce0d0"))
		canvas.draw_rect(Rect2(blade + Vector2(-1, 7), Vector2(4, 2)), Color("d4973f"))
	elif role == "merchant":
		canvas.draw_rect(Rect2(5, -9, 4, 6), Color("d4973f"))
		canvas.draw_rect(Rect2(6, -8, 1, 3), Color("f9e0b5"))
	elif role == "fence":
		canvas.draw_rect(Rect2(-4, -15, 8, 2), Color("d4973f"))


static func draw_guard_state(canvas: CanvasItem, state: int) -> void:
	if state == 1 or state == 3:
		var ink: Color = Color("f9e0b5") if state == 1 else Color("8ed4cc")
		canvas.draw_rect(Rect2(-2, -33, 4, 1), ink)
		canvas.draw_rect(Rect2(1, -32, 1, 3), ink)
		canvas.draw_rect(Rect2(-1, -29, 2, 1), ink)
		canvas.draw_rect(Rect2(-1, -26, 1, 1), ink)
	elif state == 2:
		canvas.draw_rect(Rect2(-1, -33, 2, 5), Color("e6564c"))
		canvas.draw_rect(Rect2(-1, -26, 2, 2), Color("e6564c"))
