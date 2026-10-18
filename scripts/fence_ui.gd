class_name FenceUI
extends Panel

signal closed
signal trade_requested

var _quest: LampQuest
var _dialogue: Label
var _message: Label
var _action: Button
var _trade: Button
var _close_button: Button


func setup(quest: LampQuest) -> void:
	if _quest != null and _quest.changed.is_connected(_refresh):
		_quest.changed.disconnect(_refresh)
	_quest = quest
	if _dialogue == null:
		_build()
	if _quest != null:
		_quest.changed.connect(_refresh)
	_message.text = ""
	_refresh()


func close() -> void:
	hide()
	closed.emit()


func focus_default() -> void:
	if _action != null:
		(_trade if _action.disabled else _action).grab_focus()


func _build() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2(7, 22)
	size = Vector2(306, 142)
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 10
	# Godot's bundled Noto Sans includes the Russian glyphs used here.
	theme = ui_theme
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.08, 0.06, 0.12, 1.0)
	background.border_color = Color(0.6, 0.45, 0.24, 1.0)
	background.set_border_width_all(1)
	add_theme_stylebox_override("panel", background)
	var title := Label.new()
	title.text = "Скупщик · Заказ на лампу"
	title.position = Vector2(6, 3)
	title.size = Vector2(294, 16)
	add_child(title)
	_dialogue = Label.new()
	_dialogue.name = "Dialogue"
	_dialogue.position = Vector2(6, 24)
	_dialogue.size = Vector2(294, 53)
	_dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_dialogue)
	_message = Label.new()
	_message.name = "Message"
	_message.position = Vector2(6, 79)
	_message.size = Vector2(294, 29)
	_message.add_theme_font_size_override("font_size", 9)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_message)
	_action = Button.new()
	_action.name = "QuestAction"
	_action.position = Vector2(6, 113)
	_action.size = Vector2(126, 23)
	_action.pressed.connect(_act)
	add_child(_action)
	_trade = Button.new()
	_trade.name = "Trade"
	_trade.text = "Скупка"
	_trade.position = Vector2(136, 113)
	_trade.size = Vector2(76, 23)
	_trade.pressed.connect(func() -> void: trade_requested.emit())
	add_child(_trade)
	_close_button = Button.new()
	_close_button.name = "Close"
	_close_button.text = "Закрыть"
	_close_button.position = Vector2(216, 113)
	_close_button.size = Vector2(84, 23)
	_close_button.pressed.connect(close)
	add_child(_close_button)


func _refresh() -> void:
	if _dialogue == null:
		return
	if _quest == null:
		_dialogue.text = "Заказ недоступен."
		_action.disabled = true
		return
	_dialogue.text = _quest.get_dialogue()
	var stage: LampQuest.Stage = _quest.get_stage()
	_action.text = "Принять заказ" if stage == LampQuest.Stage.OFFERED else "Передать лампу"
	if stage == LampQuest.Stage.COMPLETED:
		_action.text = "Выполнено"
	_action.disabled = stage in [LampQuest.Stage.ACCEPTED, LampQuest.Stage.COMPLETED]


func _act() -> void:
	if _quest == null:
		return
	var success: bool = _quest.accept_order() if _quest.get_stage() == LampQuest.Stage.OFFERED else _quest.hand_over()
	_message.text = "" if success else _quest.last_error
	_refresh()
