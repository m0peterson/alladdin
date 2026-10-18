extends Node2D


func _draw() -> void:
	draw_rect(Rect2(8, 24, 624, 400), Color("674b40"))
	draw_rect(Rect2(16, 48, 608, 368), Color("ad8054"))
	# Distinct ground and paths communicate the block without adding mechanics.
	draw_rect(Rect2(32, 152, 208, 152), Color("c29a62"))
	draw_rect(Rect2(48, 320, 128, 80), Color("ad8964"))
	draw_rect(Rect2(400, 272, 208, 128), Color("c09765"))
	draw_rect(Rect2(432, 96, 152, 96), Color("8a7059"))
	draw_rect(Rect2(240, 48, 176, 48), Color("89735b"))
	draw_rect(Rect2(336, 96, 80, 88), Color("89735b"))
	draw_rect(Rect2(416, 120, 40, 32), Color("89735b"))
	draw_rect(Rect2(224, 288, 304, 32), Color("d1a66b"))
	draw_rect(Rect2(488, 192, 32, 128), Color("d1a66b"))
	for x: int in range(32, 624, 16):
		for y: int in range(64, 416, 16):
			if (int(x / 16.0) + int(y / 16.0)) % 3 == 0:
				draw_rect(Rect2(x, y, 3, 1), Color(0.3, 0.2, 0.16, 0.12))
	# Door thresholds stay on the ground, below the Y-sorted walls and actors.
	draw_rect(Rect2(488, 192, 32, 16), Color("dfbd80"))
	draw_rect(Rect2(416, 120, 16, 32), Color("b6a07a"))
