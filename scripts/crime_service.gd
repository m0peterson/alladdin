class_name CrimeService
extends RefCounted

signal crime_witnessed(event: Dictionary, witness_ids: Array[String])

var _guards: Array = []
var _owners: Array = []
var _busy: bool = false


func configure(guards: Array, owners: Array) -> void:
	_guards = guards.duplicate()
	_owners = owners.duplicate()


func on_theft_completed(event: Dictionary) -> bool:
	if _busy or event.get("position") is not Vector2:
		return false
	var position_snapshot: Vector2 = event["position"]
	var witnesses: Array[String] = []
	for guard: Node2D in _guards:
		if is_instance_valid(guard) and guard.can_see(position_snapshot):
			witnesses.append(str(guard.get("guard_id")))
	# Only the nearest actor belonging to this owner can witness this theft.
	var nearest: CrimeWitness
	var nearest_distance: float = INF
	for owner: CrimeWitness in _owners:
		if not is_instance_valid(owner) or not owner.is_inside_tree() or owner.owner_id != str(event.get("owner_id", "")) or owner.owner_id.is_empty():
			continue
		var distance: float = owner.global_position.distance_squared_to(position_snapshot)
		if distance < nearest_distance:
			nearest = owner
			nearest_distance = distance
	if nearest != null and nearest.can_see(position_snapshot):
		witnesses.append(nearest.owner_id)
	if witnesses.is_empty():
		return false
	_busy = true
	# Reports contain a value snapshot only. No player reference is retained.
	for guard: Node2D in _guards:
		if is_instance_valid(guard):
			guard.report_crime(position_snapshot)
	crime_witnessed.emit(event.duplicate(true), witnesses.duplicate())
	_busy = false
	return true
