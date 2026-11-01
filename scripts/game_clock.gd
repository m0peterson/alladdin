class_name GameClock
extends Node

signal day_changed(day: int)

const DAY_SECONDS: float = 360.0
const MAX_DAY: int = 2147483647
var day_index: int = 0
var seconds_in_day: float = 0.0
var _trades: TradeService
var _busy: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func setup(trades: TradeService) -> void:
	_trades = trades


func is_busy() -> bool:
	return _busy


func _process(delta: float) -> void:
	advance(delta)


# Simulation delta only. Loading and offline time never call advance.
func advance(delta: float) -> bool:
	if _busy or not is_finite(delta) or delta < 0.0:
		return false
	if is_inside_tree() and get_tree().paused:
		return true
	var elapsed: float = seconds_in_day + delta
	# Check bounds before conversion/addition, including an enormous finite delta.
	if not is_finite(elapsed) or floor(elapsed / DAY_SECONDS) > MAX_DAY - day_index:
		return false
	var next_day: int = day_index + int(floor(elapsed / DAY_SECONDS))
	var remaining: float = fmod(elapsed, DAY_SECONDS)
	if next_day == day_index:
		seconds_in_day = remaining
		return true
	_busy = true
	if _trades == null or not _trades.refill_for_day(next_day, false):
		_busy = false
		return false
	day_index = next_day
	seconds_in_day = remaining
	# Every observer sees settled time, stocks, budgets and refill markers.
	_trades.changed.emit()
	day_changed.emit(day_index)
	_busy = false
	return true


func save_snapshot() -> Dictionary:
	return {"day_index": day_index, "seconds_in_day": seconds_in_day}


static func validate_snapshot(data: Variant) -> String:
	if data is not Dictionary or data.size() != 2 or not TradeService._integer_in(data.get("day_index"), 0, MAX_DAY):
		return "Неверный игровой день."
	var seconds: Variant = data.get("seconds_in_day")
	if (seconds is not float and seconds is not int) or not is_finite(float(seconds)) or seconds < 0 or seconds >= DAY_SECONDS:
		return "Неверное время игрового дня."
	return ""


# Silent: WorldSave first checks marker == day_index across the whole snapshot.
func restore_snapshot(data: Variant) -> bool:
	if _busy or not validate_snapshot(data).is_empty():
		return false
	day_index = int(data["day_index"])
	seconds_in_day = float(data["seconds_in_day"])
	return true
