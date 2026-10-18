class_name CrimeWitness
extends Node2D

# Attach to the owner's actor at its feet. Identity is a persistent world ID.
@export var owner_id: String = ""
@export var facing: Vector2 = Vector2.DOWN
@export var visibility: VisibilityQuery = VisibilityQuery.new()


func can_see(position_snapshot: Vector2, excluded: Array[RID] = []) -> bool:
	var exclusions: Array[RID] = excluded.duplicate()
	if get_parent() is CollisionObject2D:
		exclusions.append((get_parent() as CollisionObject2D).get_rid())
	return visibility.can_see(self, position_snapshot, facing, exclusions)
