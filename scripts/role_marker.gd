extends StaticBody2D

# Static roles; optional child Interaction handles dialogue, without AI or trade.
@export_enum("merchant", "fence", "bandit", "guard") var role: String = "merchant"
@export var tint: Color = Color("ba7047")


func _draw() -> void:
	draw_rect(Rect2(-5, -2, 4, 2), Color("402e34"))
	draw_rect(Rect2(1, -2, 4, 2), Color("402e34"))
	draw_rect(Rect2(-4, -13, 8, 11), tint)
	draw_rect(Rect2(-3, -20, 6, 7), Color("e0ae75"))
	match role:
		"merchant":
			draw_rect(Rect2(-4, -21, 8, 3), Color("f0d49a"))
			draw_rect(Rect2(3, -10, 4, 6), Color("d2a245"))
		"fence":
			draw_rect(Rect2(-4, -21, 8, 4), tint.darkened(0.4))
			draw_rect(Rect2(-3, -15, 7, 3), Color("dfb76c"))
		"bandit":
			draw_rect(Rect2(-4, -20, 8, 2), Color("b64b42"))
			draw_rect(Rect2(5, -12, 2, 10), Color("c8bfb0"))
		"guard":
			draw_rect(Rect2(-4, -22, 8, 5), Color("b6c3c4"))
			draw_rect(Rect2(6, -25, 1, 24), Color("b6c3c4"))
