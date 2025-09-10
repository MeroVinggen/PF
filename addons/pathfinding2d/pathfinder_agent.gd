@tool
extends Node2D
class_name PathfinderAgent

signal path_found(path: PackedVector2Array)
signal destination_reached()
signal path_blocked()
signal agent_stuck()
signal agent_unstuck()
signal path_invalidated()
signal path_recalculated()

@export var agent_radius: float = 10.0 : 
	set(value):
		agent_radius = value
		agent_full_size = agent_radius + agent_buffer
@export var agent_buffer: float = 2.0 :
	set(value):
		agent_buffer = value
		agent_full_size = agent_radius + agent_buffer
@export_flags_2d_physics var mask: int = 1

@onready var agent_full_size: float = agent_radius + agent_buffer

var system: PathfinderSystem
var validator: PathValidator
var current_path: PackedVector2Array = PackedVector2Array()
var target_position: Vector2
var path_index: int = 0
var is_moving: bool = false

var pending_pathfinding_request: bool = false
var consecutive_failed_recalcs: int = 0

var last_spatial_position: Vector2 = Vector2.INF
var spatial_update_threshold: float = 20.0 

func _physics_process(delta: float):
	if not system or Engine.is_editor_hint():
		return
	# Check if agent moved enough to warrant spatial partition update
	if last_spatial_position.distance_to(global_position) > spatial_update_threshold:
		system.spatial_partition.update_agent(self)
		last_spatial_position = global_position

func _exit_tree():
	if system and not Engine.is_editor_hint():
		system.unregister_pathfinder(self)

func _recalculate_or_find_alternative():
	if validator.is_circle_position_unsafe(target_position, agent_full_size):
		consecutive_failed_recalcs = 0
		return
	
	consecutive_failed_recalcs += 1
	
	if consecutive_failed_recalcs >= PathfindingConstants.MAX_FAILED_RECALCULATIONS:
		_pause_and_retry()
		return
	
	system.array_pool.return_packedVector2_array(current_path)
	var path = system.find_path_for_circle(global_position, target_position, agent_full_size, mask)
	
	if path.is_empty():
		# Try nearby positions around target
		var angles = [0, PI/4, PI/2, 3*PI/4, PI, 5*PI/4, 3*PI/2, 7*PI/4]
		for angle in angles:
			var offset = Vector2(cos(angle), sin(angle)) * (agent_full_size * PathfindingConstants.ALTERNATIVE_POSITION_RADIUS_MULTIPLIER)
			var test_pos = target_position + offset
			if _is_point_in_bounds(test_pos) and not validator.is_circle_position_unsafe(test_pos, agent_full_size):
				system.array_pool.return_packedVector2_array(current_path)
				path = system.find_path_for_circle(global_position, test_pos, agent_full_size, mask)
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
	
	if pending_pathfinding_request:
		return false
	
	# If destination is unsafe, find closest safe point
	var safe_destination = destination
	if validator.is_circle_position_unsafe(destination, agent_full_size):
		print("Destination is inside obstacle, finding closest safe point...")
		safe_destination = system._find_closest_safe_point(destination, agent_full_size)
		
		if safe_destination == Vector2.INF:
			print("Could not find any safe point near destination")
			path_blocked.emit()
			return false
		
		print("Redirected to safe point: ", safe_destination, " (distance: ", destination.distance_to(safe_destination), ")")
	
	target_position = safe_destination
	pending_pathfinding_request = true
	system.request_queue.queue_request(self, global_position, safe_destination, agent_full_size, mask)
	return true

func get_next_waypoint() -> Vector2:
	if current_path.is_empty() or path_index >= current_path.size():
		return Vector2.INF
	
	var next_point = current_path[path_index]
	
	# Check if this waypoint is now unsafe
	if validator.is_circle_position_unsafe(next_point, agent_full_size):
		print("UNSAFE")
		# First try: find a close safe alternative without full recalculation
		var safe_alternative = system._find_closest_safe_point(next_point, agent_full_size)
		
		if safe_alternative != Vector2.INF and next_point.distance_to(safe_alternative) < agent_full_size * 3:
			if validator.is_safe_circle_path(global_position, safe_alternative, agent_full_size):
				current_path[path_index] = safe_alternative
				return safe_alternative
		
		# If no safe path to alternative OR large deviation - trigger full recalculation
		_recalculate_or_find_alternative()
		if path_index < current_path.size():
			return current_path[path_index]
		return Vector2.INF
	else:
		print("SAFE")
	
	return next_point

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
	system.array_pool.return_packedVector2_array(current_path)
	path_index = 0
	consecutive_failed_recalcs = 0
	destination_reached.emit()
	
	# Update spatial partition since we stopped moving
	if system:
		system.spatial_partition.update_agent(self)
		last_spatial_position = global_position

func get_current_path() -> PackedVector2Array:
	return current_path

func is_path_valid() -> bool:
	if not validator:
		return false
	return validator.is_path_safe(current_path, global_position, path_index, agent_full_size)

func recalculate_path():
	if is_moving:
		_recalculate_or_find_alternative()

func stop_movement():
	is_moving = false
	current_path.clear()
	system.array_pool.return_packedVector2_array(current_path)
	path_index = 0
	target_position = Vector2.ZERO
	
	# Update spatial partition
	if system:
		system.spatial_partition.update_agent(self)
		last_spatial_position = global_position

func _on_queued_path_result(path: PackedVector2Array):
	pending_pathfinding_request = false
	
	if path.is_empty():
		path_blocked.emit()
		return
	
	current_path = path
	path_index = 0
	is_moving = true
	consecutive_failed_recalcs = 0
	path_found.emit(current_path)
	
	# Update spatial partition since we're starting to move
	if system:
		system.spatial_partition.update_agent(self)
		last_spatial_position = global_position
