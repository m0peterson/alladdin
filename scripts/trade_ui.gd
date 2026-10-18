class_name TradeUI
extends Panel

signal closed

var _service: TradeService
var _state: PlayerState
var _inventory: ItemInventory
var _merchant_id: String
var _buying: bool = true
var _title: Label
var _rows: VBoxContainer
var _message: Label
var _buy_button: Button
var _sell_button: Button


func setup(service: TradeService, player_state: PlayerState, inventory: ItemInventory, merchant_id: String) -> void:
	if _service != null and _service.changed.is_connected(_refresh):
		_service.changed.disconnect(_refresh)
	_service = service
	_state = player_state
	_inventory = inventory
	_merchant_id = merchant_id
	_buying = true
	if _title == null:
		_build()
	_service.changed.connect(_refresh)
	_message.text = "Цены за штуку. Сделка: 1 предмет."
	_refresh()


func close() -> void:
	hide()
	closed.emit()


func _build() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2(7, 22)
	size = Vector2(306, 142)
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 10
	theme = ui_theme
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.06, 0.12, 1.0)
	panel_style.border_color = Color(0.6, 0.45, 0.24, 1.0)
	panel_style.set_border_width_all(1)
	add_theme_stylebox_override("panel", panel_style)
	_title = Label.new()
	_title.position = Vector2(6, 3)
	_title.size = Vector2(294, 15)
	add_child(_title)
	_buy_button = Button.new()
	_buy_button.text = "Купить"
	_buy_button.position = Vector2(6, 22)
	_buy_button.size = Vector2(85, 20)
	_buy_button.pressed.connect(_switch_mode.bind(true))
	add_child(_buy_button)
	_sell_button = Button.new()
	_sell_button.text = "Продать"
	_sell_button.position = Vector2(95, 22)
	_sell_button.size = Vector2(85, 20)
	_sell_button.pressed.connect(_switch_mode.bind(false))
	add_child(_sell_button)
	var close_button := Button.new()
	close_button.name = "Close"
	close_button.text = "Закрыть"
	close_button.position = Vector2(213, 22)
	close_button.size = Vector2(87, 20)
	close_button.pressed.connect(close)
	add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.position = Vector2(6, 46)
	scroll.size = Vector2(294, 67)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 1)
	scroll.add_child(_rows)
	_message = Label.new()
	_message.position = Vector2(6, 116)
	_message.size = Vector2(294, 23)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", 9)
	add_child(_message)


func _switch_mode(buying: bool) -> void:
	_buying = buying
	_message.text = "Цены за штуку. Сделка: 1 предмет."
	_refresh()


func _refresh() -> void:
	if _title == null or _service == null:
		return
	var merchant: Dictionary = _service.get_merchant(_merchant_id)
	if merchant.is_empty():
		_title.text = "Торговец недоступен"
		return
	_title.text = "%s · Вы: %d · Он: %d д." % [merchant["name"], _state.money, merchant["budget"]]
	_buy_button.disabled = _buying
	_sell_button.disabled = not _buying
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var stacks: Array = merchant["stacks"] if _buying else _inventory.get_stacks()
	for stack: Dictionary in stacks:
		var item: Dictionary = ItemCatalog.get_item(stack["item_id"])
		var row := HBoxContainer.new()
		_rows.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var marker: String = " (краденое)" if stack["stolen"] else ""
		label.text = "%s ×%d%s" % [item.get("name", stack["item_id"]), stack["quantity"], marker]
		row.add_child(label)
		var action := Button.new()
		var price: int = _service.get_offer_price(_merchant_id, stack["item_id"], _buying)
		var refusal: String = _service.get_trade_refusal(_merchant_id, stack, _buying)
		action.text = "%s %d д." % ["Купить" if _buying else "Продать", price]
		action.tooltip_text = str(item.get("description", ""))
		# Refused goods stay actionable so the player receives a visible reason.
		if not refusal.is_empty():
			action.text = "Отказ"
			action.tooltip_text = refusal
		action.pressed.connect(_transact.bind(str(stack["stack_id"])))
		row.add_child(action)
	if stacks.is_empty():
		var empty := Label.new()
		empty.text = "Нет товаров." if _buying else "Инвентарь пуст."
		_rows.add_child(empty)


func _transact(stack_id: String) -> void:
	var success: bool
	if _buying:
		success = _service.buy(_merchant_id, stack_id, 1, _state, _inventory)
	else:
		success = _service.sell(_merchant_id, stack_id, 1, _state, _inventory)
	_message.text = "Сделка завершена." if success else _service.last_error
	_refresh()
