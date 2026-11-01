extends StaticBody2D

# The origin is the lower edge of the footprint, shared with the player's feet.
@export var footprint: Vector2 = Vector2(48, 16)
@export var rise: float = 20.0
@export var cloth: bool = false
@export var tint: Color = Color("b78958")


func _ready() -> void:
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = footprint
	$CollisionShape2D.shape = shape
	$CollisionShape2D.position = Vector2(0, -footprint.y / 2.0)
	queue_redraw()


func _draw() -> void:
	var left: float = -footprint.x / 2.0
	# Preserve the existing footprint, collision and Y-sort origin.
	draw_rect(Rect2(left, -footprint.y - rise, footprint.x, footprint.y + rise), Color("533746"))
	draw_rect(Rect2(left + 1, -footprint.y - rise + 1, footprint.x - 2, footprint.y - 1), tint.lightened(0.24))
	draw_rect(Rect2(left + 1, -rise, footprint.x - 2, rise - 1), tint)
	draw_rect(Rect2(left + 1, -rise, footprint.x - 2, 2), tint.lightened(0.28))
	if footprint.x <= 20.0 and footprint.y <= 12.0:
		_draw_chest(left)
	elif cloth:
		for x: int in range(int(left + 1), int(-left - 1), 8):
			draw_rect(Rect2(x, -footprint.y - rise + 1, 4, footprint.y + 1), tint.lightened(0.35))
			draw_rect(Rect2(x, -rise + 1, 4, 2), tint.darkened(0.2))
		draw_rect(Rect2(left + 3, -rise + 5, footprint.x - 6, 5), Color("533746"))
		for x: int in range(int(left + 5), int(-left - 5), 7):
			draw_rect(Rect2(x, -rise + 5, 4, 3), Color("d4973f"))
			draw_rect(Rect2(x + 1, -rise + 4, 2, 1), Color("f9e0b5"))
	else:
		for y: int in range(int(-rise + 6), -2, 7):
			draw_rect(Rect2(left + 1, y, footprint.x - 2, 1), tint.darkened(0.25))
			var offset: int = 8 if (y / 7) % 2 == 0 else 0
			for x: int in range(int(left + 2 + offset), int(-left - 1), 16):
				draw_rect(Rect2(x, y - 5, 1, 5), tint.darkened(0.2))
		for x: int in range(int(left + 3), int(-left - 2), 12):
			draw_rect(Rect2(x, -footprint.y - rise + 2, 4, 1), Color("dfbd80"))


func _draw_chest(left: float) -> void:
	for x: float in [left + 3, -left - 5]:
		draw_rect(Rect2(x, -footprint.y - rise + 1, 2, footprint.y + rise - 2), Color("d4973f"))
	draw_rect(Rect2(-2, -rise + 2, 4, 4), Color("533746"))
	draw_rect(Rect2(-1, -rise + 3, 2, 2), Color("f9e0b5"))
	var target: TheftTarget = get_node_or_null("Interaction") as TheftTarget
	if target == null or target.stock.get_stacks().is_empty():
		if target != null:
			draw_rect(Rect2(left + 2, -footprint.y - rise + 2, footprint.x - 4, footprint.y - 3), Color("402e34"))
		return
	var icon: Texture2D = preload("res://assets/items/lamp.svg") if target.get_loot().get("item_id") == "lamp" else preload("res://assets/items/silk.svg")
	draw_texture_rect(icon, Rect2(-8, -footprint.y - rise - 9, 16, 16), false)
	draw_rect(Rect2(-10, -footprint.y - rise - 5, 1, 3), Color("f9e0b5"))
	draw_rect(Rect2(9, -footprint.y - rise - 5, 1, 3), Color("f9e0b5"))


func _process(_delta: float) -> void:
	# Stock is installed after _ready and may empty on a theft. Read only.
	if footprint.x <= 20.0 and footprint.y <= 12.0:
		queue_redraw()
