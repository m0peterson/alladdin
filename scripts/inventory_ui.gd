class_name InventoryUI
extends Panel

signal closed

var player_state: PlayerState
var inventory: ItemInventory
var item_list: ItemList
var use_button: Button
var close_button: Button
var _details: Label
var _health: Label
var _stack_ids: Array[String] = []
var _selected_id: String = ""


func _ready() -> void:
	offset_left = 8
	offset_top = 22
	offset_right = 312
	offset_bottom = 164
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color(0.13, 0.10, 0.14, 1.0)
	add_theme_stylebox_override("panel", background)
	add_theme_font_size_override("font_size", 10)
	var title: Label = Label.new()
	title.text = "Инвентарь"
	title.position = Vector2(8, 3)
	title.add_theme_font_size_override("font_size", 12)
	add_child(title)
	_health = Label.new()
	_health.position = Vector2(154, 4)
	_health.add_theme_font_size_override("font_size", 10)
	add_child(_health)
	item_list = ItemList.new()
	item_list.name = "Items"
	item_list.position = Vector2(8, 23)
	item_list.size = Vector2(138, 85)
	item_list.fixed_icon_size = Vector2i(16, 16)
	item_list.add_theme_font_size_override("font_size", 10)
	item_list.item_selected.connect(_select_item)
	add_child(item_list)
	_details = Label.new()
	_details.position = Vector2(154, 23)
	_details.size = Vector2(142, 85)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_size_override("font_size", 9)
	add_child(_details)
	use_button = Button.new()
	use_button.name = "Use"
	use_button.text = "Съесть (+25)"
	use_button.position = Vector2(8, 113)
	use_button.size = Vector2(138, 23)
	use_button.add_theme_font_size_override("font_size", 10)
	use_button.pressed.connect(_use_selected)
	add_child(use_button)
	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = "Закрыть · I / Esc"
	close_button.position = Vector2(154, 113)
	close_button.size = Vector2(142, 23)
	close_button.add_theme_font_size_override("font_size", 10)
	close_button.pressed.connect(func() -> void: closed.emit())
	add_child(close_button)
	_refresh()


func focus_default() -> void:
	if close_button != null:
		close_button.grab_focus()


# The game controller owns input routing, pause, visibility and return focus.
func setup(state: PlayerState, items: ItemInventory) -> void:
	if inventory != null and inventory.changed.is_connected(_refresh):
		inventory.changed.disconnect(_refresh)
	if player_state != null and player_state.changed.is_connected(_refresh):
		player_state.changed.disconnect(_refresh)
	player_state = state
	inventory = items
	_selected_id = ""
	if inventory != null:
		inventory.changed.connect(_refresh)
	if player_state != null:
		player_state.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if item_list == null:
		return
	item_list.clear()
	_stack_ids.clear()
	if inventory != null:
		for stack: Dictionary in inventory.get_stacks():
			var item: Dictionary = ItemCatalog.get_item(stack["item_id"])
			var mark: String = " *" if stack["stolen"] else ""
			var icon: Texture2D = load(item["icon"]) as Texture2D
			item_list.add_item("%s ×%d%s" % [item["name"], stack["quantity"], mark], icon)
			_stack_ids.append(stack["stack_id"])
	if not _stack_ids.is_empty():
		var selected: int = _stack_ids.find(_selected_id)
		if selected < 0:
			selected = 0
		item_list.select(selected)
		_selected_id = _stack_ids[selected]
	else:
		_selected_id = ""
	_health.text = "Здоровье: %d/%d" % [player_state.health, PlayerState.MAX_HEALTH] if player_state != null else ""
	_update_details()


func _select_item(index: int) -> void:
	_selected_id = _stack_ids[index]
	_update_details()


func _update_details() -> void:
	use_button.disabled = true
	if inventory == null or _selected_id.is_empty():
		_details.text = "Инвентарь пуст."
		_details.tooltip_text = ""
		return
	var stack: Dictionary = inventory.get_stack(_selected_id)
	var item: Dictionary = ItemCatalog.get_item(stack["item_id"])
	var origin: String = "Краденое *" if stack["stolen"] else "Законный предмет"
	if item["type"] == "quest":
		origin += " · квест"
	_details.text = "%s\n%s\nЦена: %d дин." % [item["description"], origin, item["price"]]
	_details.tooltip_text = "Владелец: %s\nИсточник: %s\nЭкземпляр: %s" % [stack["owner_id"], stack["source_id"], stack["instance_id"]]
	use_button.text = "Съесть (+%d)" % item["heal"] if item["type"] == "food" else "Применить"
	use_button.disabled = not (item["type"] == "food" and item["usable"] and player_state != null and player_state.health > 0 and player_state.health < PlayerState.MAX_HEALTH)


func _use_selected() -> void:
	if inventory != null:
		inventory.use_food(_selected_id, player_state)
