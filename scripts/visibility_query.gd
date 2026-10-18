class_name VisibilityQuery
extends Resource

# Stateless geometry query: future witnesses can share these parameters without
# acquiring a target, remembering positions, or changing any actor state.
@export_range(0.0, 1000.0) var max_distance: float = 112.0
@export_range(0.0, 360.0) var sector_degrees: float = 100.0
@export_flags_2d_physics var occluder_mask: int = 1


func can_see(observer: Node2D, target_position: Vector2, facing: Vector2,
		excluded: Array[RID] = []) -> bool:
	if not is_instance_valid(observer) or not observer.is_inside_tree():
		return false
	var origin: Vector2 = observer.global_position
	var offset: Vector2 = target_position - origin
	if offset.length_squared() > max_distance * max_distance:
		return false
	if not offset.is_zero_approx():
		if facing.is_zero_approx():
			return false
		var threshold: float = cos(deg_to_rad(sector_degrees * 0.5))
		if facing.normalized().dot(offset.normalized()) < threshold - 0.00001:
			return false
	else:
		return true
	var exclusions: Array[RID] = excluded.duplicate()
	if observer is CollisionObject2D:
		exclusions.append((observer as CollisionObject2D).get_rid())
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		origin, target_position, occluder_mask, exclusions)
	ray.hit_from_inside = true
	return observer.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()
