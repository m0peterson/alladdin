class_name ItemCatalog
extends RefCounted

# Stable item IDs and metadata are content, independent of inventory and GUI.
enum ItemType { GOODS, FOOD, QUEST }
const LAMP_INSTANCE_ID: String = "quest_lamp"
const DATA_PATH: String = "res://data/items.json"
static var _items: Dictionary = {}


static func get_item(item_id: String) -> Dictionary:
	_load_data()
	return (_items.get(item_id, {}) as Dictionary).duplicate(true)


static func get_item_ids() -> Array[String]:
	_load_data()
	var ids: Array[String] = []
	for item_id: String in _items:
		ids.append(item_id)
	return ids


static func _load_data() -> void:
	if not _items.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is not Dictionary:
		push_error("Item catalog is not a dictionary: " + DATA_PATH)
		return
	_items = parsed
	# JSON numbers are floats; money and healing use integer data throughout play.
	for item: Dictionary in _items.values():
		item["price"] = int(item["price"])
		item["heal"] = int(item.get("heal", 0))
