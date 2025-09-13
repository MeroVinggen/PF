@tool
extends Node2D
class_name PathfinderAgent

signal path_found(path: PackedVector2Array)
signal destination_reached()
signal path_blocked()
signal agent_stuck()
signal agent_unstuck()
signal path_recalculated()

@export var agent_radius: float = 10.0 : 
	set(value):
		agent_radius = value
		_updateAgentMetricsBasedOnSizeAndBuffer()
@export var agent_buffer: float = 2.0 :
	set(value):
		agent_buffer = value
		_updateAgentMetricsBasedOnSizeAndBuffer()
@export_flags_2d_physics var mask: int = 1

@onready var agent_full_size: float = agent_radius + agent_buffer
@export var update_frequency: float = 30.0 : set = _set_update_frequency

var system: PathfinderSystem
var current_path: PackedVector2Array = PackedVector2Array()
var target_position: Vector2
var path_index: int = -1
var is_moving: bool = false

var pending_pathfinding_request: bool = false
var consecutive_failed_recalcs: int = 0

var last_spatial_position: Vector2 = Vector2.INF
var spatial_update_threshold: float = 0.0

var update_timer: float = 0.0
var update_interval: float = 0.0

func _set_update_frequency(value: float):
	update_frequency = max(0.0, value)
	update_interval = 1.0 / update_frequency
	print(update_interval)

# sgould be called by system or registration the agent
func register(sys: PathfinderSystem) -> void:
	system = sys
	_updateAgentMetricsBasedOnSizeAndBuffer()
	set_physics_process(true)

# sgould be called by system or unregistration the agent
func unregister() -> void:
	system = null
	set_physics_process(false)

func _updateAgentMetricsBasedOnSizeAndBuffer() -> void:
	# to prevent errs in the editor mode
	if not system:
		return
	
	agent_full_size = agent_radius + agent_buffer
	spatial_update_threshold = min(agent_full_size * 0.3, system.grid_size * 0.5)

# prevent errs in the editor mode
func _ready() -> void:
	set_physics_process(false)

func _physics_process(delta: float):
	update_timer += delta
	if update_timer < update_interval:
		return
	
	update_timer = 0.0
	#print("UPADTE")
	# Check if agent moved enough to warrant spatial partition update
	if last_spatial_position.distance_to(global_position) > spatial_update_threshold:
		system.spatial_partition.update_agent(self)
		last_spatial_position = global_position

func recalculate_or_find_alternative():
	print("recalculate_or_find_alternative")
	if PathfindingUtils.is_circle_position_unsafe(system, target_position, agent_full_size, mask):
		consecutive_failed_recalcs = 0
		return
	
	consecutive_failed_recalcs += 1
	
	if consecutive_failed_recalcs >= PathfindingConstants.MAX_FAILED_RECALCULATIONS:
		_pause_and_retry()
		return
	
	system.array_pool.return_packedVector2_array(current_path)
	var path = PathfindingUtils.find_path_for_circle(system, global_position, target_position, agent_full_size, mask)
	
	if path.is_empty():
		# Try nearby positions around target
		var angles = [0, PI/4, PI/2, 3*PI/4, PI, 5*PI/4, 3*PI/2, 7*PI/4]
		for angle in angles:
			var offset = Vector2(cos(angle), sin(angle)) * (agent_full_size * PathfindingConstants.ALTERNATIVE_POSITION_RADIUS_MULTIPLIER)
			var test_pos = target_position + offset
			if PathfindingUtils.is_point_in_polygon(test_pos, system.bounds_polygon) and not PathfindingUtils.is_circle_position_unsafe(system, test_pos, agent_full_size, mask):
				system.array_pool.return_packedVector2_array(current_path)
				path = PathfindingUtils.find_path_for_circle(system, global_position, test_pos, agent_full_size, mask)
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

# checks destination is available(or pick new one) and make queue_request
func find_path_to(destination: Vector2) -> bool:
	if not system:
		push_error("pathfinding system should be set for pathfinder")
		return false
	
	if pending_pathfinding_request:
		return false
	
	# If destination is unsafe, find closest safe point
	var safe_destination = destination
	if PathfindingUtils.is_circle_position_unsafe(system, destination, agent_full_size, mask):
		print("Destination is inside obstacle, finding closest safe point...")
		safe_destination = PathfindingUtils.find_closest_safe_point(system, destination, agent_full_size, mask)
		
		if safe_destination == Vector2.INF:
			print("Could not find any safe point near destination")
			path_blocked.emit()
			return false
		
		print("Redirected to safe point: ", safe_destination, " (distance: ", destination.distance_to(safe_destination), ")")
	
	target_position = safe_destination
	pending_pathfinding_request = true
	system.request_queue.queue_request(self, global_position, safe_destination, agent_full_size, mask)
	return true


func get_next_waypoint_with_auto_rebuilt() -> Vector2:
	if current_path.is_empty():
		return Vector2.INF
	
	if pending_pathfinding_request:
		return Vector2.ZERO
	
	var next_point = current_path[path_index]
	
	# Check if current waypoint is unsafe
	if PathfindingUtils.is_circle_position_unsafe(system, next_point, agent_full_size, mask):
		# First try: find a close safe alternative without full recalculation
		var safe_alternative = PathfindingUtils.find_closest_safe_point(system, next_point, agent_full_size, mask)
		
		#if safe_alternative != Vector2.INF and next_point.distance_to(safe_alternative) < agent_full_size * 3:
		if safe_alternative != Vector2.INF:
			if PathfindingUtils.is_safe_circle_path(system, global_position, safe_alternative, agent_full_size, mask):
				current_path[path_index] = safe_alternative
				return safe_alternative
		
		# If no safe path to alternative - trigger full recalculation
		find_path_to(target_position)
		return Vector2.ZERO
	
	# check if current path segment is unsafe (from cur agent pos) - trigger full recalculation
	if not PathfindingUtils.is_path_safe(system, current_path, global_position, path_index, agent_full_size, mask):
		if find_path_to(target_position):
			return Vector2.ZERO
		else:
			return Vector2.INF
	
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
	path_index = -1
	consecutive_failed_recalcs = 0
	destination_reached.emit()
	
	# Update spatial partition since we stopped moving
	if system:
		system.spatial_partition.update_agent(self)
		last_spatial_position = global_position

func stop_movement():
	is_moving = false
	current_path.clear()
	system.array_pool.return_packedVector2_array(current_path)
	path_index = -1
	target_position = Vector2.ZERO
	
	# Update spatial partition
	if system:
		system.spatial_partition.update_agent(self)
		last_spatial_position = global_position

# pathfinding result for "find_path_to" call
func _on_queued_path_result(path: PackedVector2Array):
	pending_pathfinding_request = false
	
	if path.is_empty():
		path_blocked.emit()
		return
	
	current_path = path
	path_index = 0
	#is_moving = true
	consecutive_failed_recalcs = 0
	#path_found.emit(current_path)
	call_deferred("emit_signal", "path_found", current_path)
	
	# Update spatial partition since we're starting to move
	if system:
		system.spatial_partition.update_agent(self)
		last_spatial_position = global_position
