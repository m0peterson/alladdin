extends StaticBody2D

# Static roles; optional child Interaction handles dialogue, without AI or trade.
@export_enum("merchant", "fence", "bandit", "guard") var role: String = "merchant"
@export var tint: Color = Color("ba7047")


func _draw() -> void:
	CharacterVisual.draw_actor(self, role)
