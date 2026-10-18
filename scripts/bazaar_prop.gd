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
	draw_rect(Rect2(left, -footprint.y - rise, footprint.x, footprint.y), tint.lightened(0.18))
	draw_rect(Rect2(left, -rise, footprint.x, rise), tint)
	draw_rect(Rect2(left, -2, footprint.x, 2), tint.darkened(0.35))
	if cloth:
		for x: int in range(int(left), int(-left), 8):
			draw_rect(Rect2(x, -footprint.y - rise, 4, footprint.y + 3), tint.lightened(0.35))
		draw_rect(Rect2(left + 3, -rise + 4, footprint.x - 6, 4), Color("dfb76c"))
	else:
		for y: int in range(int(-rise + 8), -2, 8):
			draw_line(Vector2(left, y), Vector2(-left, y), tint.darkened(0.18))
		for x: int in range(int(left + 16), int(-left), 16):
			draw_line(Vector2(x, -rise), Vector2(x, -2), tint.darkened(0.12))
