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
	# Deterministic pixel texture: no random flicker.
	for x: int in range(32, 624, 16):
		for y: int in range(64, 416, 16):
			var shift: int = (x * 7 + y * 11) % 13
			draw_rect(Rect2(x + shift, y, 3, 1), Color("b78b5e"))
			if (x + y) % 48 == 0:
				draw_rect(Rect2(x + shift, y - 1, 2, 1), Color("d1a66b"))
	for area: Rect2i in [Rect2i(240, 48, 176, 48), Rect2i(336, 96, 80, 88), Rect2i(488, 208, 32, 112)]:
		for y: int in range(area.position.y, area.end.y, 8):
			for x: int in range(area.position.x, area.end.x, 16):
				var offset: int = 4 if (y / 8) % 2 == 0 else 0
				draw_rect(Rect2(x + offset, y, 11, 5), Color("a58b6b"))
				draw_rect(Rect2(x + offset, y, 11, 1), Color("c3a580"))
	_rug(Rect2i(64, 208, 48, 24), Color("84423e"))
	_rug(Rect2i(168, 264, 48, 24), Color("366966"))
	_rug(Rect2i(72, 344, 40, 24), Color("644471"))
	# Door thresholds stay on the ground, below the Y-sorted walls and actors.
	draw_rect(Rect2(488, 192, 32, 16), Color("dfbd80"))
	draw_rect(Rect2(416, 120, 16, 32), Color("b6a07a"))


func _rug(area: Rect2i, ink: Color) -> void:
	draw_rect(Rect2(area), Color("533746"))
	draw_rect(Rect2(area.grow(-1)), ink)
	draw_rect(Rect2(area.grow(-3)), Color("d4973f"), false, 1.0)
	for x: int in range(area.position.x + 6, area.end.x - 4, 8):
		draw_rect(Rect2(x, area.position.y + 9, 3, 3), Color("f9e0b5"))
	for x: int in range(area.position.x + 2, area.end.x, 3):
		draw_rect(Rect2(x, area.end.y, 1, 2), Color("d4973f"))
