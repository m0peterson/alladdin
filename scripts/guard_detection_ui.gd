class_name GuardDetectionUI
extends Control

var _guards: Array = []
var _label: Label
var _bar: ProgressBar


func setup(guards: Array) -> void:
	_guards = guards.duplicate()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(88, 22)
	_label = Label.new()
	_label.position = Vector2.ZERO
	_label.add_theme_font_size_override("font_size", 9)
	add_child(_label)
	_bar = ProgressBar.new()
	_bar.position = Vector2(0, 13)
	_bar.size = Vector2(144, 5)
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)


func _process(_delta: float) -> void:
	if get_tree().paused:
		hide()
		return
	var strongest: int = GuardPatrol.State.PATROL
	var amount: float = 0.0
	for entry: Variant in _guards:
		if not is_instance_valid(entry):
			continue
		var guard: GuardPatrol = entry as GuardPatrol
		if guard == null:
			continue
		amount = maxf(amount, guard.suspicion)
		if guard.state == GuardPatrol.State.CHASE:
			strongest = GuardPatrol.State.CHASE
		elif guard.state == GuardPatrol.State.SEARCH and strongest != GuardPatrol.State.CHASE:
			strongest = GuardPatrol.State.SEARCH
		elif guard.state == GuardPatrol.State.SUSPICIOUS and strongest == GuardPatrol.State.PATROL:
			strongest = GuardPatrol.State.SUSPICIOUS
	visible = strongest != GuardPatrol.State.PATROL
	_label.text = {GuardPatrol.State.SUSPICIOUS: "Стража: подозрение", GuardPatrol.State.CHASE: "Тревога! Преследование", GuardPatrol.State.SEARCH: "Стража ищет вас"}.get(strongest, "")
	_label.modulate = Color("ffb670") if strongest == GuardPatrol.State.CHASE else Color("ffe4a0")
	_bar.value = amount
