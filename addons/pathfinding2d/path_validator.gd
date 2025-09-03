@tool
extends RefCounted
class_name PathValidator

var system: PathfinderSystem

func _init(pathfinder_system: PathfinderSystem):
	system = pathfinder_system

func is_path_safe(path: PackedVector2Array, current_pos: Vector2, path_index: int, radius: float, buffer: float) -> bool:
	if not system or path.is_empty() or path_index >= path.size():
		return false
	
	# Check current position
	if is_circle_position_unsafe(current_pos, radius, buffer):
		return false
	
	# Check next waypoint
	if path_index < path.size():
		var next_waypoint = path[path_index]
		if is_circle_position_unsafe(next_waypoint, radius, buffer):
			return false
		if not is_safe_circle_path(current_pos, next_waypoint, radius, buffer):
			return false
	
	return true

func is_circle_position_unsafe(pos: Vector2, radius: float, buffer: float) -> bool:
	return system._is_circle_position_unsafe(pos, radius, buffer)

func is_safe_circle_path(start: Vector2, end: Vector2, radius: float, buffer: float) -> bool:
	return system._is_safe_circle_path(start, end, radius, buffer)

func find_closest_safe_point(unsafe_pos: Vector2, radius: float, buffer: float) -> Vector2:
	return system._find_closest_safe_point(unsafe_pos, radius, buffer)
