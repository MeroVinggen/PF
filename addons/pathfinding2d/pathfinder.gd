@tool
extends Node2D
class_name Pathfinder

signal path_found(path: PackedVector2Array)
signal destination_reached()
signal path_blocked()
signal agent_stuck()
signal agent_unstuck()
signal path_invalidated()
signal path_recalculated()

@export var agent_radius: float = 10.0
@export var agent_buffer: float = 2.0

var system: PathfinderSystem
var validator: PathValidator
var current_path: PackedVector2Array = PackedVector2Array()
var target_position: Vector2
var path_index: int = 0
var is_moving: bool = false

var consecutive_failed_recalcs: int = 0

func _exit_tree():
	if system and not Engine.is_editor_hint():
		system.unregister_pathfinder(self)

func _on_obstacles_changed():
	print("DEBUG: Pathfinder received obstacles_changed signal")
	if not is_moving or current_path.is_empty() or not validator:
		return
		
	if not validator.is_path_safe(current_path, global_position, path_index, agent_radius, agent_buffer):
		path_invalidated.emit()
		consecutive_failed_recalcs = 0
		_recalculate_or_find_alternative()

func _recalculate_or_find_alternative():
	consecutive_failed_recalcs += 1
	
	if consecutive_failed_recalcs >= PathfindingConstants.MAX_FAILED_RECALCULATIONS:
		_pause_and_retry()
		return
	
	if system.is_grid_dirty():
		system.force_grid_update()
	
	var path = system.find_path_for_circle(global_position, target_position, agent_radius)
	
	if path.is_empty():
		# Try nearby positions around target
		var angles = [0, PI/4, PI/2, 3*PI/4, PI, 5*PI/4, 3*PI/2, 7*PI/4]
		for angle in angles:
			var offset = Vector2(cos(angle), sin(angle)) * (agent_radius * PathfindingConstants.ALTERNATIVE_POSITION_RADIUS_MULTIPLIER)
			var test_pos = target_position + offset
			if _is_point_in_bounds(test_pos) and not validator.is_circle_position_unsafe(test_pos, agent_radius, agent_buffer):
				path = system.find_path_for_circle(global_position, test_pos, agent_radius)
				if not path.is_empty():
					target_position = test_pos
					break
		
		if path.is_empty():
			_pause_and_retry()
			return
	
	current_path = path
	path_index = 0
	consecutive_failed_recalcs = 0
	path_recalculated.emit()

func _pause_and_retry():
	is_moving = false
	consecutive_failed_recalcs = 0
	
	var timer = get_tree().create_timer(PathfindingConstants.RETRY_DELAY_SECONDS)
	timer.timeout.connect(func(): 
		print("Retrying pathfinding...")
		if find_path_to(target_position):
			print("Retry successful")
	)

func _is_point_in_bounds(point: Vector2) -> bool:
	return PathfindingUtils.is_point_in_polygon(point, system.bounds_polygon)

func find_path_to(destination: Vector2) -> bool:
	if not system:
		push_error("pathfinding system should be set for pathfinder")
		return false
	
	# If destination is unsafe, find closest safe point
	var safe_destination = destination
	if validator.is_circle_position_unsafe(destination, agent_radius, agent_buffer):
		print("Destination is inside obstacle, finding closest safe point...")
		safe_destination = validator.find_closest_safe_point(destination, agent_radius, agent_buffer)
		
		if safe_destination == Vector2.INF:
			print("Could not find any safe point near destination")
			path_blocked.emit()
			return false
		
		print("Redirected to safe point: ", safe_destination, " (distance: ", destination.distance_to(safe_destination), ")")
	
	var path = system.find_path_for_circle(global_position, safe_destination, agent_radius, agent_buffer)
	
	if path.is_empty():
		path_blocked.emit()
		return false
	
	current_path = path
	target_position = safe_destination
	path_index = 0
	is_moving = true
	
	consecutive_failed_recalcs = 0
	
	path_found.emit(current_path)
	return true

func move_to(destination: Vector2) -> bool:
	return find_path_to(destination)

func get_next_waypoint() -> Vector2:
	if current_path.is_empty() or path_index >= current_path.size():
		return Vector2.INF
	return current_path[path_index]

func advance_to_next_waypoint() -> bool:
	path_index += 1
	if path_index >= current_path.size():
		_on_destination_reached()
		return false
	return true

func get_remaining_distance() -> float:
	if current_path.is_empty() or path_index >= current_path.size():
		return 0.0
	
	var total = 0.0
	for i in range(path_index, current_path.size() - 1):
		total += current_path[i].distance_to(current_path[i + 1])
	return total

func _on_destination_reached():
	is_moving = false
	current_path.clear()
	path_index = 0
	consecutive_failed_recalcs = 0
	destination_reached.emit()

func get_current_path() -> PackedVector2Array:
	return current_path

func is_path_valid() -> bool:
	if not validator:
		return false
	return validator.is_path_safe(current_path, global_position, path_index, agent_radius, agent_buffer)

func recalculate_path():
	if is_moving:
		_recalculate_or_find_alternative()

func _get_configuration_warnings() -> PackedStringArray:
	return PathfindingValidator.validate_pathfinder(self)
