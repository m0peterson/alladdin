class_name TheftUI
extends Control

var _controller: TheftController
var _label: Label
var _progress: ProgressBar
var _message_time: float = 0.0


func setup(controller: TheftController) -> void:
	if is_instance_valid(_controller):
		_controller.progress_changed.disconnect(_update_progress)
		_controller.status_changed.disconnect(_show_status)
	_controller = controller
	if _label == null:
		_build()
	_controller.progress_changed.connect(_update_progress)
	_controller.status_changed.connect(_show_status)


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(8, 123)
	size = Vector2(304, 18)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_shadow_color", Color(0.06, 0.04, 0.03, 1.0))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_progress = ProgressBar.new()
	_progress.position = Vector2(0, 14)
	_progress.size = Vector2(140, 4)
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress)
	hide()


func _update_progress(ratio: float, active: bool) -> void:
	_progress.visible = active
	_progress.value = ratio
	if active:
		_label.text = "Кража: удерживайте F"
		_message_time = 0.0
		show()
	elif _message_time <= 0.0:
		hide()


func _show_status(message: String) -> void:
	_label.text = message
	_message_time = 2.0
	show()


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			hide()
