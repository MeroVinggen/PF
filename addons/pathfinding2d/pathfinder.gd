@tool
extends Node2D
class_name Pathfinder

@export var agent_radius: float = 10.0
@export var movement_speed: float = 200.0
@export var rotation_speed: float = 5.0
@export var auto_move: bool = true
@export var debug_draw: bool = true
@export var agent_color: Color = Color.GREEN
@export var path_color: Color = Color.YELLOW
@export var arrival_distance: float = 8.0

# Stuck prevention settings
@export var stuck_threshold: float = 2.0
@export var stuck_time_threshold: float = 2.0
@export var unstuck_force: float = 50.0
@export var corner_avoidance_distance: float = 20.0

# Dynamic pathfinding settings
@export var path_validation_rate: float = 0.2  # How often to validate current path (seconds)
@export var auto_recalculate: bool = true  # Automatically recalculate when path becomes invalid

@export var fast_validation_mode: bool = true  # Enable for dynamic environments
@export var validation_lookahead: int = 3  # How many waypoints ahead to validate


var system: PathfinderSystem
var current_path: PackedVector2Array = PackedVector2Array()
var target_position: Vector2
var path_index: int = 0
var is_moving: bool = false

# Stuck detection variables
var last_positions: Array[Vector2] = []
var stuck_timer: float = 0.0
var unstuck_direction: Vector2 = Vector2.ZERO
var is_unsticking: bool = false
var last_recalc_time: float = 0.0
var recalc_cooldown: float = 1.0

# Dynamic pathfinding variables
var path_validation_timer: float = 0.0
var last_path_hash: int = 0
var consecutive_failed_recalcs: int = 0
var max_failed_recalcs: int = 3

signal path_found(path: PackedVector2Array)
signal destination_reached()
signal path_blocked()
signal agent_stuck()
signal agent_unstuck()
signal path_invalidated()
signal path_recalculated()

func _ready():
	add_to_group("pathfinders")
	if not Engine.is_editor_hint():
		call_deferred("_find_system")

func _find_system():
	system = get_tree().get_first_node_in_group("pathfinder_systems") as PathfinderSystem
	if system:
		system.register_pathfinder(self)
		print("Pathfinder connected to system")
	else:
		print("Warning: No PathfinderSystem found!")
		await get_tree().create_timer(0.1).timeout
		_find_system()

func _exit_tree():
	if system and not Engine.is_editor_hint():
		system.unregister_pathfinder(self)

func _physics_process(delta: float) -> void:
	queue_redraw()

func _process(delta):
	if Engine.is_editor_hint() or not auto_move:
		return
	
	_update_dynamic_pathfinding(delta)
	
	if is_moving:
		_update_stuck_detection(delta)
		_follow_path(delta)

func _update_dynamic_pathfinding(delta):
	"""Simplified dynamic path validation"""
	if not is_moving or current_path.is_empty():
		return
	
	path_validation_timer += delta
	
	# Adaptive validation rate
	var validation_rate = path_validation_rate
	if fast_validation_mode and system and system.get_dynamic_obstacle_count() > 0:
		validation_rate *= 0.5
	
	if path_validation_timer >= validation_rate:
		path_validation_timer = 0.0
		
		if not _is_path_segment_valid():
			print("Path segment invalid - attempting recalculation")
			path_invalidated.emit()
			_handle_path_invalidation()

func _is_path_segment_valid() -> bool:
	"""Check immediate path segment validity"""
	if not system or current_path.is_empty() or path_index >= current_path.size():
		return false
	
	# Check current position
	if system._is_circle_position_unsafe(global_position, agent_radius):
		return false
	
	# Check next 2 waypoints maximum
	var check_count = min(2, current_path.size() - path_index)
	
	for i in range(path_index, path_index + check_count):
		var waypoint = current_path[i]
		
		if system._is_circle_position_unsafe(waypoint, agent_radius):
			return false
		
		if i == path_index:
			if not system._is_safe_circle_path(global_position, waypoint, agent_radius):
				return false
	
	return true

func _handle_path_invalidation():
	"""Simplified path invalidation handling"""
	# Reset failure count periodically to prevent permanent lockup
	if Time.get_time_dict_from_system().get("second", 0) % 5 == 0:
		consecutive_failed_recalcs = 0
	
	if consecutive_failed_recalcs >= max_failed_recalcs:
		print("Too many failures, pausing briefly...")
		_pause_and_retry()
		return
	
	# Try simple recalculation first
	if _simple_recalculation():
		return
	
	# Try fallback strategies
	_try_fallback_strategies()

func _try_fallback_strategies():
	"""Try simple fallback strategies"""
	var strategies = [
		_try_nearby_target,
		_try_wait_strategy,
		_try_reverse_movement
	]
	
	for strategy in strategies:
		if strategy.call():
			return
	
	# Last resort: pause
	_pause_and_retry()

func _pause_and_retry():
	"""Pause movement and retry after delay"""
	is_moving = false
	consecutive_failed_recalcs = 0  # Reset failure count
	
	print("Pausing movement, will retry soon...")
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(_retry_after_pause)

func _retry_after_pause():
	"""Retry pathfinding after pause"""
	print("Retrying pathfinding after pause...")
	if find_path_to(target_position):
		print("Successfully found path after pause")
	else:
		# Try again with longer delay
		var timer = get_tree().create_timer(3.0)
		timer.timeout.connect(_retry_after_pause)

func _try_reverse_movement() -> bool:
	"""Try moving back along current path"""
	if current_path.size() <= 1 or path_index <= 0:
		return false
	
	# Find a safe previous waypoint
	for i in range(min(path_index - 1, current_path.size() - 1), -1, -1):
		var reverse_target = current_path[i]
		if not system._is_circle_position_unsafe(reverse_target, agent_radius):
			var path = system.find_path_for_circle(global_position, reverse_target, agent_radius)
			if not path.is_empty():
				current_path = path
				path_index = 0
				print("Reversing to previous waypoint")
				return true
	
	return false

func _try_wait_strategy() -> bool:
	"""Wait for dynamic obstacles to move"""
	if system.get_dynamic_obstacle_count() > 0:
		print("Waiting for dynamic obstacles to move...")
		is_moving = false
		
		# Set up retry timer
		var timer = get_tree().create_timer(1.0)
		timer.timeout.connect(_retry_after_wait)
		return true
	
	return false

func _retry_after_wait():
	"""Retry pathfinding after waiting"""
	consecutive_failed_recalcs = max(0, consecutive_failed_recalcs - 1)  # Reduce failure count
	
	if find_path_to(target_position):
		print("Successfully found path after waiting")
	else:
		print("Still blocked, will try again...")
		_try_wait_strategy()

func _try_nearby_target() -> bool:
	"""Try pathfinding to nearby safe positions around target"""
	var nearby_positions = []
	var angles = [0, PI/4, PI/2, 3*PI/4, PI, 5*PI/4, 3*PI/2, 7*PI/4]
	
	for angle in angles:
		var offset = Vector2(cos(angle), sin(angle)) * (agent_radius * 3)
		var test_pos = target_position + offset
		
		if _is_point_in_polygon(test_pos, system.bounds_polygon) and \
		   not system._is_circle_position_unsafe(test_pos, agent_radius):
			nearby_positions.append(test_pos)
	
	for pos in nearby_positions:
		var path = system.find_path_for_circle(global_position, pos, agent_radius)
		if not path.is_empty():
			current_path = path
			path_index = 0
			target_position = pos  # Update target
			print("Found path to nearby target: ", pos)
			return true
	
	return false

func _simple_recalculation() -> bool:
	"""Simple path recalculation to original target"""
	if not system:
		return false
	
	consecutive_failed_recalcs += 1
	
	# Force grid update
	if system.is_grid_dirty():
		system.force_grid_update()
	
	# Try pathfinding to original target
	var path = system.find_path_for_circle(global_position, target_position, agent_radius)
	
	if not path.is_empty():
		current_path = path
		path_index = 0
		consecutive_failed_recalcs = 0
		path_recalculated.emit()
		print("Simple recalculation successful")
		return true
	
	return false



func _pause_for_obstacle_movement():
	"""Pause movement and retry after a delay"""
	is_moving = false
	
	# Set up a timer to retry pathfinding
	var retry_timer = get_tree().create_timer(1.0)
	retry_timer.timeout.connect(_retry_pathfinding_after_pause)
	
	print("Pausing movement, will retry in 1 second")

func _retry_pathfinding_after_pause():
	"""Retry pathfinding after pause"""
	print("Retrying pathfinding after pause...")
	
	# Reset failure count and try again
	consecutive_failed_recalcs = 0
	
	if find_path_to(target_position):
		print("Successfully found path after pause")
	else:
		print("Still no path available - will try again when obstacles move")
		# Set up another retry if we're still stuck
		var retry_timer = get_tree().create_timer(2.0)
		retry_timer.timeout.connect(_retry_pathfinding_after_pause)



func _try_reverse_path_movement() -> bool:
	"""Try moving backwards along the current path"""
	if current_path.size() <= 1 or path_index <= 0:
		return false
	
	# Find a previous waypoint that's still safe
	for i in range(path_index - 1, -1, -1):
		var reverse_target = current_path[i]
		if not system._is_circle_position_unsafe(reverse_target, agent_radius):
			print("Trying reverse movement to waypoint ", i)
			if _internal_find_path_to(reverse_target):
				print("Successfully found reverse path")
				return true
	
	return false



func _find_nearby_safe_positions(count: int) -> Array[Vector2]:
	"""Find nearby safe positions for emergency movement"""
	var safe_positions: Array[Vector2] = []
	var search_radius = agent_radius * 3
	var max_search_radius = agent_radius * 10
	
	while safe_positions.size() < count and search_radius <= max_search_radius:
		var angles = []
		for i in 16:  # Check 16 directions
			angles.append((i * TAU) / 16)
		
		for angle in angles:
			var test_pos = global_position + Vector2(cos(angle), sin(angle)) * search_radius
			
			if _is_point_in_polygon(test_pos, system.bounds_polygon) and \
			   not system._is_circle_position_unsafe(test_pos, agent_radius):
				safe_positions.append(test_pos)
				
				if safe_positions.size() >= count:
					break
		
		search_radius += agent_radius * 2
	
	# Sort by distance to original target
	if target_position != Vector2.ZERO:
		safe_positions.sort_custom(func(a, b): return target_position.distance_squared_to(a) < target_position.distance_squared_to(b))
	
	return safe_positions


func _internal_find_path_to(destination: Vector2) -> bool:
	"""Internal pathfinding without state reset"""
	if not system:
		return false
	
	var path = system.find_path_for_circle(global_position, destination, agent_radius)
	
	if path.is_empty():
		return false
	
	current_path = path
	target_position = destination
	path_index = 0
	is_moving = true
	
	# Only reset some state, keep stuck detection running
	path_validation_timer = 0.0
	last_path_hash = _calculate_path_hash(path)
	
	return true



func _generate_nearby_safe_positions(center: Vector2, radius: float, count: int) -> Array[Vector2]:
	"""Generate safe positions around a center point"""
	var positions: Array[Vector2] = []
	
	for i in count:
		var angle = (i * TAU) / count
		var test_pos = center + Vector2(cos(angle), sin(angle)) * radius
		
		# Check if position is within bounds and safe
		if _is_point_in_polygon(test_pos, system.bounds_polygon) and \
		   not system._is_circle_position_unsafe(test_pos, agent_radius):
			positions.append(test_pos)
	
	# Sort by distance to current position
	positions.sort_custom(func(a, b): return global_position.distance_squared_to(a) < global_position.distance_squared_to(b))
	
	return positions

func _extract_valid_path_segments(path: PackedVector2Array, start_index: int) -> PackedVector2Array:
	"""Extract valid segments from the remaining path"""
	if not system or path.is_empty() or start_index >= path.size():
		return PackedVector2Array()
	
	var valid_path = PackedVector2Array()
	valid_path.append(global_position)  # Start from current position
	
	# Check each remaining segment
	for i in range(start_index, path.size()):
		var segment_start = valid_path[-1] if valid_path.size() > 0 else global_position
		var segment_end = path[i]
		
		# If this segment is safe, add the endpoint
		if system._is_safe_circle_path(segment_start, segment_end, agent_radius):
			valid_path.append(segment_end)
		else:
			# Stop at first invalid segment
			break
	
	# Need at least 2 points for a valid path
	if valid_path.size() < 2:
		return PackedVector2Array()
	
	return valid_path


func _generate_fallback_targets() -> Array[Vector2]:
	"""Generate fallback target positions for alternative pathfinding"""
	var fallback_targets: Array[Vector2] = []
	var original_target = target_position
	
	# Generate points in a circle around the original target
	var fallback_radius = [50.0, 100.0, 150.0]
	var angle_steps = 8
	
	for radius in fallback_radius:
		for i in angle_steps:
			var angle = (i * TAU) / angle_steps
			var fallback_pos = original_target + Vector2(cos(angle), sin(angle)) * radius
			fallback_targets.append(fallback_pos)
	
	# Sort by distance to current position (closer first)
	fallback_targets.sort_custom(func(a, b): return global_position.distance_squared_to(a) < global_position.distance_squared_to(b))
	
	return fallback_targets



func _is_point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return true

	var inside = false
	var j = polygon.size() - 1

	for i in polygon.size():
		var pi = polygon[i]
		var pj = polygon[j]

		if ((pi.y > point.y) != (pj.y > point.y)) and \
			(point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x):
			inside = !inside
		j = i

	return inside

func _update_stuck_detection(delta):
	"""Simplified stuck detection"""
	last_positions.append(global_position)
	if last_positions.size() > 8:
		last_positions.pop_front()
	
	if last_positions.size() < 4:
		return
	
	var movement = last_positions[-1].distance_to(last_positions[0])
	
	if movement < stuck_threshold:
		stuck_timer += delta
		if stuck_timer >= stuck_time_threshold:
			_handle_simple_stuck()
	else:
		stuck_timer = 0.0
		if is_unsticking:
			is_unsticking = false
			agent_unstuck.emit()

func _handle_simple_stuck():
	"""Simple stuck handling"""
	print("Agent stuck - trying simple recovery")
	agent_stuck.emit()
	is_unsticking = true
	
	# Try simple movement in random directions
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	directions.shuffle()
	
	for direction in directions:
		var test_pos = global_position + direction * (agent_radius * 2)
		if not system._is_circle_position_unsafe(test_pos, agent_radius):
			unstuck_direction = direction
			print("Found unstuck direction: ", direction)
			return
	
	# If no direction works, try recalculating path
	consecutive_failed_recalcs = 0  # Reset to allow fresh attempts
	_handle_path_invalidation()

func _handle_stuck_situation():
	"""Handle when the agent gets stuck"""
	print("Agent appears stuck! Attempting recovery...")
	agent_stuck.emit()
	is_unsticking = true
	
	# Try different recovery strategies in order
	if not _try_corner_avoidance():
		if not _try_path_recalculation():
			_try_emergency_movement()

func _try_corner_avoidance() -> bool:
	"""Try to move away from nearby corners"""
	if not system:
		return false
	
	var avoidance_force = Vector2.ZERO
	var found_corner = false
	
	for obstacle in system.obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var world_poly = obstacle.get_world_polygon()
		var corners = system._find_obstacle_corners(world_poly)
		
		for corner in corners:
			var distance = global_position.distance_to(corner)
			if distance < corner_avoidance_distance:
				found_corner = true
				var repulsion = (global_position - corner).normalized()
				var strength = (corner_avoidance_distance - distance) / corner_avoidance_distance
				avoidance_force += repulsion * strength * unstuck_force
	
	if found_corner:
		unstuck_direction = avoidance_force.normalized()
		print("Applying corner avoidance force: ", unstuck_direction)
		return true
	
	return false

func _try_path_recalculation() -> bool:
	"""Try recalculating the path"""
	return _simple_recalculation()

func _try_emergency_movement():
	"""Last resort: try random movement directions"""
	print("Using emergency movement to get unstuck")
	
	var directions = [
		Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT,
		Vector2.UP + Vector2.LEFT, Vector2.UP + Vector2.RIGHT,
		Vector2.DOWN + Vector2.LEFT, Vector2.DOWN + Vector2.RIGHT
	]
	
	for direction in directions:
		var test_pos = global_position + direction * unstuck_force
		if system and not system._is_circle_position_unsafe(test_pos, agent_radius):
			unstuck_direction = direction
			print("Found emergency direction: ", direction)
			return
	
	if last_positions.size() >= 2:
		var last_movement = last_positions[-1] - last_positions[-2]
		unstuck_direction = -last_movement.normalized()
	else:
		unstuck_direction = Vector2.UP

func find_path_to(destination: Vector2) -> bool:
	"""Simplified pathfinding with better error handling"""
	if not system:
		print("No pathfinding system available")
		return false
	
	print("Finding path to: ", destination)
	
	# Direct pathfinding attempt
	var path = system.find_path_for_circle(global_position, destination, agent_radius)
	
	if path.is_empty():
		print("Direct pathfinding failed")
		path_blocked.emit()
		return false
	
	# Success - set up path following
	current_path = path
	target_position = destination
	path_index = 0
	is_moving = true
	
	# Reset all state
	stuck_timer = 0.0
	is_unsticking = false
	last_positions.clear()
	path_validation_timer = 0.0
	consecutive_failed_recalcs = 0
	
	print("Path found with ", path.size(), " waypoints")
	path_found.emit(current_path)
	return true

func _calculate_path_hash(path: PackedVector2Array) -> int:
	"""Calculate a hash for the path to detect changes"""
	var hash_string = ""
	for point in path:
		hash_string += str(int(point.x)) + "," + str(int(point.y)) + ";"
	return hash_string.hash()

func move_to(destination: Vector2):
	if find_path_to(destination):
		is_moving = true
	else:
		print("No path found to destination")

func stop_movement():
	is_moving = false
	current_path.clear()
	path_index = 0
	is_unsticking = false
	stuck_timer = 0.0
	path_validation_timer = 0.0

func _follow_path(delta):
	if current_path.is_empty() or path_index >= current_path.size():
		_on_destination_reached()
		return
	
	# Handle unstuck movement
	if is_unsticking and unstuck_direction.length() > 0.1:
		_apply_unstuck_movement(delta)
		return
	
	var current_target = current_path[path_index]
	var distance_to_target = global_position.distance_to(current_target)
	
	# Check if we've reached the current waypoint
	if distance_to_target < arrival_distance:
		path_index += 1
		if path_index >= current_path.size():
			_on_destination_reached()
			return
		current_target = current_path[path_index]
		distance_to_target = global_position.distance_to(current_target)
	
	# Enhanced collision prediction
	if system and _will_movement_cause_collision(current_target, delta):
		print("Movement would cause collision! Handling...")
		_handle_collision_avoidance(current_target, delta)
		return
	
	# Normal movement
	var direction = (current_target - global_position).normalized()
	var movement = direction * movement_speed * delta
	
	# Don't overshoot the target
	if movement.length() > distance_to_target:
		movement = direction * distance_to_target
	
	# Apply corner avoidance force if near corners
	var avoidance_force = _calculate_corner_avoidance_force()
	if avoidance_force.length() > 0.1:
		direction = (direction + avoidance_force * 0.5).normalized()
		movement = direction * movement_speed * delta
		if movement.length() > distance_to_target:
			movement = direction * distance_to_target
	
	global_position += movement
	
	# Rotate towards movement direction
	if direction.length() > 0.1:
		var target_angle = direction.angle()
		rotation = lerp_angle(rotation, target_angle, rotation_speed * delta)

func _apply_unstuck_movement(delta):
	"""Apply movement to get unstuck"""
	var movement = unstuck_direction * unstuck_force * delta
	var new_position = global_position + movement
	
	if system and not system._is_circle_position_unsafe(new_position, agent_radius):
		global_position = new_position
		print("Applied unstuck movement")
	else:
		unstuck_direction = unstuck_direction.rotated(PI / 4)
		print("Rotated unstuck direction")

func _will_movement_cause_collision(target: Vector2, delta: float) -> bool:
	"""Predict if movement towards target will cause collision - Enhanced"""
	if not system:
		return false
	
	var direction = (target - global_position).normalized()
	var movement_distance = movement_speed * delta
	
	# Check multiple points along the movement path
	var samples = max(int(movement_distance / 5.0), 3)  # Sample every 5 units or at least 3 samples
	
	for i in range(1, samples + 1):
		var t = float(i) / float(samples)
		var test_position = global_position + direction * movement_distance * t
		
		if system._is_circle_position_unsafe(test_position, agent_radius):
			return true
	
	return false

func _handle_collision_avoidance(target: Vector2, delta: float):
	"""Simplified collision avoidance"""
	var direction_to_target = (target - global_position).normalized()
	
	# Try sliding perpendicular to target direction
	var slide_directions = [
		Vector2(-direction_to_target.y, direction_to_target.x),  # Left
		Vector2(direction_to_target.y, -direction_to_target.x)   # Right
	]
	
	for slide_dir in slide_directions:
		var test_movement = slide_dir * movement_speed * delta * 0.7
		var test_position = global_position + test_movement
		
		if not system._is_circle_position_unsafe(test_position, agent_radius):
			global_position = test_position
			print("Applied slide movement")
			return
	
	# If sliding failed, try recalculating
	if randf() < 0.2:  # 20% chance to recalculate
		_handle_path_invalidation()


func _calculate_corner_avoidance_force() -> Vector2:
	"""Calculate force to avoid nearby corners"""
	if not system:
		return Vector2.ZERO
	
	var avoidance_force = Vector2.ZERO
	
	for obstacle in system.obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var world_poly = obstacle.get_world_polygon()
		var corners = system._find_obstacle_corners(world_poly)
		
		for corner in corners:
			var distance = global_position.distance_to(corner)
			if distance < corner_avoidance_distance:
				var repulsion = (global_position - corner).normalized()
				var strength = (corner_avoidance_distance - distance) / corner_avoidance_distance
				avoidance_force += repulsion * strength
	
	return avoidance_force.normalized()

func _on_destination_reached():
	is_moving = false
	current_path.clear()
	path_index = 0
	is_unsticking = false
	stuck_timer = 0.0
	path_validation_timer = 0.0
	consecutive_failed_recalcs = 0
	print("Pathfinder: Destination reached!")
	destination_reached.emit()

func get_current_path() -> PackedVector2Array:
	return current_path

func is_path_valid() -> bool:
	"""Enhanced path validation"""
	if not system or current_path.is_empty():
		return false
	
	# Quick check: is current position safe?
	if system._is_circle_position_unsafe(global_position, agent_radius):
		return false
	
	# Check remaining path segments with more granular sampling
	for i in range(path_index, current_path.size() - 1):
		var start = current_path[i]
		var end = current_path[i + 1]
		
		# Check endpoints
		if system._is_circle_position_unsafe(start, agent_radius) or \
		   system._is_circle_position_unsafe(end, agent_radius):
			return false
		
		# Check path with higher resolution for dynamic obstacles
		if not _is_detailed_path_safe(start, end):
			return false
	
	return true

func _is_detailed_path_safe(start: Vector2, end: Vector2) -> bool:
	"""Detailed path safety check with high resolution"""
	if not system:
		return false
	
	var distance = start.distance_to(end)
	var samples = max(int(distance / 3.0), 5)  # Sample every 3 units minimum
	
	for i in range(samples + 1):
		var t = float(i) / float(samples)
		var test_pos = start.lerp(end, t)
		
		if system._is_circle_position_unsafe(test_pos, agent_radius):
			return false
	
	return true

func recalculate_path():
	"""Manually trigger path recalculation"""
	if not is_moving:
		return
	
	_simple_recalculation()

func _draw() -> void:
	if not debug_draw:
		return
	
	# Draw agent circle with status coloring
	var color = agent_color
	if consecutive_failed_recalcs > 0:
		color = Color.PURPLE  # Path recalculation issues
	elif is_unsticking:
		color = Color.ORANGE  # Unsticking
	elif stuck_timer > stuck_time_threshold * 0.7:
		color = Color.YELLOW  # Getting stuck
	elif not is_path_valid() and is_moving:
		color = Color.RED  # Invalid path
	
	draw_circle(Vector2.ZERO, agent_radius, color * 0.7)
	draw_arc(Vector2.ZERO, agent_radius, 0, TAU, 32, color, 2.0)
	
	# Draw current path with validation status
	if current_path.size() > 1:
		for i in range(current_path.size() - 1):
			var start = to_local(current_path[i])
			var end = to_local(current_path[i + 1])
			
			# Color path segments based on validity
			var segment_color = path_color
			if i >= path_index:
				# Check if this segment is still valid
				if system and not system._is_safe_circle_path(current_path[i], current_path[i + 1], agent_radius):
					segment_color = Color.RED
			else:
				segment_color = Color.GRAY  # Already passed
			
			draw_line(start, end, segment_color, 3.0)
		
		# Draw waypoints
		for i in range(current_path.size()):
			var point = to_local(current_path[i])
			var color_waypoint = path_color
			if i == path_index:
				color_waypoint = Color.WHITE  # Current target
			elif i < path_index:
				color_waypoint = Color.GRAY  # Passed waypoints
			draw_circle(point, 5.0, color_waypoint)
	
	# Draw target position
	if is_moving and target_position != Vector2.ZERO:
		var target_local = to_local(target_position)
		draw_circle(target_local, 8.0, Color.MAGENTA)
	
	# Draw dynamic status indicators
	if path_validation_timer > 0:
		# Path validation progress indicator
		var progress = path_validation_timer / path_validation_rate
		var indicator_pos = Vector2(0, -agent_radius - 15)
		var indicator_size = Vector2(20, 3)
		draw_rect(Rect2(indicator_pos - indicator_size * 0.5, indicator_size), Color.BLACK)
		draw_rect(Rect2(indicator_pos - indicator_size * 0.5, Vector2(indicator_size.x * progress, indicator_size.y)), Color.CYAN)
	
	# Draw recalculation failure count
	if consecutive_failed_recalcs > 0:
		var warning_pos = Vector2(agent_radius + 5, -5)
		for i in consecutive_failed_recalcs:
			draw_circle(warning_pos + Vector2(i * 8, 0), 3.0, Color.RED)
	
	# Other existing debug drawing...
	if corner_avoidance_distance > 0:
		draw_arc(Vector2.ZERO, corner_avoidance_distance, 0, TAU, 32, Color.CYAN * 0.3, 1.0)
	
	if is_unsticking and unstuck_direction.length() > 0.1:
		var arrow_end = unstuck_direction * 20
		draw_line(Vector2.ZERO, arrow_end, Color.RED, 3.0)
		var arrow_size = 5.0
		var arrow_angle = 0.5
		draw_line(arrow_end, arrow_end - unstuck_direction.rotated(arrow_angle) * arrow_size, Color.RED, 2.0)
		draw_line(arrow_end, arrow_end - unstuck_direction.rotated(-arrow_angle) * arrow_size, Color.RED, 2.0)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if agent_radius <= 0:
		warnings.append("Agent radius must be greater than 0")
	
	if movement_speed <= 0:
		warnings.append("Movement speed must be greater than 0")
	
	if arrival_distance <= 0:
		warnings.append("Arrival distance must be greater than 0")
	
	if path_validation_rate <= 0:
		warnings.append("Path validation rate must be greater than 0")
	
	if path_validation_rate < 0.1:
		warnings.append("Very low path validation rate may cause performance issues")
	
	return warnings

# Helper functions
func get_distance_to_target() -> float:
	if current_path.is_empty() or path_index >= current_path.size():
		return 0.0
	return global_position.distance_to(current_path[path_index])

func get_distance_to_destination() -> float:
	if target_position == Vector2.ZERO:
		return 0.0
	return global_position.distance_to(target_position)

func is_stuck() -> bool:
	return stuck_timer >= stuck_time_threshold

func get_stuck_progress() -> float:
	return stuck_timer / stuck_time_threshold

func get_path_validation_progress() -> float:
	return path_validation_timer / path_validation_rate

func get_failed_recalc_count() -> int:
	return consecutive_failed_recalcs

func is_path_being_validated() -> bool:
	return is_moving and current_path.size() > 0
