class_name InteractionTarget
extends Node2D

enum Kind { NPC, CONTAINER }

const INTERACTION_DISTANCE: float = 32.0

@export var target_id: String = ""
@export var display_name: String = ""
@export var kind: Kind = Kind.NPC
@export_multiline var message: String = ""
@export var enabled: bool = true

var opened: bool = false


func _ready() -> void:
	add_to_group("interaction_targets")


func is_available(actor: Node2D) -> bool:
	if not is_instance_valid(actor) or not is_inside_tree() or not actor.is_inside_tree():
		return false
	if not enabled or target_id.is_empty() or not is_visible_in_tree():
		return false
	if get_tree().paused or not actor.can_process():
		return false
	if actor.global_position.distance_squared_to(global_position) > INTERACTION_DISTANCE * INTERACTION_DISTANCE:
		return false
	# Both endpoints use the foot plane. The target's own collider is allowed;
	# counters and walls between the player and target block the same action.
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		actor.global_position + Vector2(0, -3), global_position + Vector2(0, -3), 1
	)
	if actor is CollisionObject2D:
		query.exclude = [(actor as CollisionObject2D).get_rid()]
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == get_parent()


func prompt() -> String:
	var verb: String = "Говорить"
	if kind == Kind.CONTAINER:
		verb = "Осмотреть" if opened else "Открыть"
	return "E — %s: %s" % [verb, display_name]


func interact(actor: Node2D) -> String:
	if not is_available(actor):
		return ""
	if kind == Kind.CONTAINER:
		opened = true
	return message
