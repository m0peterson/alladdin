class_name TrainingDummy
extends Node2D

signal damaged(amount: int)

var total_damage: int = 0
var hit_count: int = 0
var _flash: float = 0.0


func _ready() -> void:
	add_to_group("damageable")
	queue_redraw()


func receive_damage(amount: int, _origin: Vector2 = Vector2.ZERO) -> bool:
	if amount <= 0:
		return false
	total_damage += amount
	hit_count += 1
	_flash = 0.18
	damaged.emit(amount)
	queue_redraw()
	return true


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()


func _draw() -> void:
	draw_ellipse_shadow()
	draw_line(Vector2(0, -2), Vector2(0, -22), Color("795536"), 3.0)
	draw_line(Vector2(-10, -15), Vector2(10, -15), Color("b39254"), 3.0)
	draw_circle(Vector2(0, -18), 7.0, Color("ffe5aa") if _flash > 0.0 else Color("bc995d"))
	draw_arc(Vector2(0, -18), 4.0, 0, TAU, 12, Color("75513d"), 1.0)


func draw_ellipse_shadow() -> void:
	draw_rect(Rect2(-7, -2, 14, 3), Color(0.15, 0.12, 0.1, 0.4))
