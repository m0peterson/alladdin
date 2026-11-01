class_name PlayerSave
extends RefCounted

const VERSION: int = 1
const DEFAULT_PATH: String = "user://player-save.json"
const MAX_FILE_BYTES: int = 1048576
const WORLD_NOTICE: String = "Сохраняется только игрок. Квартал, торговля и враги НЕ сохраняются."
var path: String


func _init(save_path: String = DEFAULT_PATH) -> void:
	path = save_path


static func integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	if value is not int and value is not float:
		return false
	return is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


func capture(position: Vector2, state: PlayerState, inventory: ItemInventory) -> Dictionary:
	return {"version": VERSION, "scope": "player", "player": {
		"position": {"x": position.x, "y": position.y}, "health": state.health,
		"money": state.money, "inventory": inventory.save_snapshot()}}


func validate(data: Variant) -> String:
	if data is not Dictionary:
		return "Сохранение повреждено: ожидается объект JSON."
	if not integer_in(data.get("version"), VERSION, VERSION):
		return "Версия сохранения не поддерживается."
	if data.get("scope") != "player" or data.get("player") is not Dictionary:
		return "Сохранение повреждено: нет данных игрока."
	var saved: Dictionary = data["player"]
	var point: Variant = saved.get("position")
	if point is not Dictionary:
		return "Неверное положение игрока."
	for axis: String in ["x", "y"]:
		var value: Variant = point.get(axis)
		if (value is not float and value is not int) or not is_finite(float(value)) or value < 0 or value > (640 if axis == "x" else 432):
			return "Положение игрока выходит за границы квартала."
	if not integer_in(saved.get("health"), 1, PlayerState.MAX_HEALTH) or not integer_in(saved.get("money"), 0, ItemInventory.MAX_QUANTITY):
		return "Неверные здоровье или динары игрока."
	return ItemInventory.validate_snapshot(saved.get("inventory"))


func read_file(file_path: String = "") -> Dictionary:
	var target: String = path if file_path.is_empty() else file_path
	if not FileAccess.file_exists(target):
		return {"ok": false, "error": "Сохранение не найдено."}
	var file: FileAccess = FileAccess.open(target, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return {"ok": false, "error": "Не удалось прочитать сохранение: файл недоступен или слишком велик."}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"ok": false, "error": "Сохранение повреждено: неверный JSON."}
	var problem: String = validate(json.data)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return {"ok": true, "data": json.data}


func has_backup() -> bool:
	return read_file(path + ".bak")["ok"]


# Verify a sibling temporary file before rename. Never delete the destination
# first: a failed write or replacement must leave the previous valid file intact.
func _write_verified(target: String, data: Dictionary) -> String:
	var temporary: String = target + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Не удалось записать сохранение. Прежний файл сохранён."
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or not read_file(temporary)["ok"]:
		DirAccess.remove_absolute(temporary)
		return "Ошибка проверки записи. Прежний файл сохранён."
	if DirAccess.rename_absolute(temporary, target) != OK:
		DirAccess.remove_absolute(temporary)
		return "Не удалось заменить файл сохранения. Прежний файл сохранён."
	return ""


func write(data: Dictionary) -> String:
	var problem: String = validate(data)
	if not problem.is_empty():
		return problem
	if FileAccess.file_exists(path):
		var previous: Dictionary = read_file()
		if not previous["ok"]:
			return "Прежнее сохранение повреждено. Восстановите резервную копию; запись отменена."
		problem = _write_verified(path + ".bak", previous["data"])
		if not problem.is_empty():
			return problem
	return _write_verified(path, data)


func restore_backup() -> Dictionary:
	var backup: Dictionary = read_file(path + ".bak")
	if not backup["ok"]:
		return backup
	var problem: String = _write_verified(path, backup["data"])
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return backup
