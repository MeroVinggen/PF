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
	"""Handle dynamic path validation and recalculation - Fixed"""
	if not is_moving or current_path.is_empty():
		return
	
	path_validation_timer += delta
	
	# Adaptive validation rate based on environment
	var validation_rate = path_validation_rate
	if fast_validation_mode and system and system.get_dynamic_obstacle_count() > 0:
		validation_rate *= 0.3  # Much more frequent validation
	
	# Validate path periodically
	if path_validation_timer >= validation_rate:
		path_validation_timer = 0.0
		
		# Enhanced validation - check immediate path AND lookahead
		if not _is_immediate_path_valid():
			print("Immediate path became invalid - attempting recalculation")
			path_invalidated.emit()
			
			if auto_recalculate:
				# Don't stop movement immediately - try to recalculate first
				if not _attempt_path_recalculation():
					print("Could not find alternative path - trying emergency strategies")
					_try_emergency_pathfinding()

func _try_emergency_pathfinding():
	"""Enhanced emergency pathfinding strategies"""
	print("Trying emergency pathfinding strategies...")
	
	# Strategy 1: Try moving to any nearby safe position
	var safe_positions = _find_nearby_safe_positions(5)
	for safe_pos in safe_positions:
		if _internal_find_path_to(safe_pos):
			print("Found emergency path to safe position: ", safe_pos)
			return
	
	# Strategy 2: Try moving backwards along current path
	if _try_reverse_path_movement():
		return
	
	# Strategy 3: Try local exploration to find clear space
	if _try_local_exploration():
		return
	
	# Strategy 4: Last resort - stop but don't give up completely
	print("Emergency pathfinding failed - pausing for obstacle to move")
	_pause_for_obstacle_movement()

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

func _try_local_exploration() -> bool:
	"""Try local exploration to find a path around the immediate obstacle"""
	# Create a small exploration pattern around current position
	var exploration_points = []
	var base_distance = agent_radius * 2
	
	# Create a spiral pattern for exploration
	for ring in range(1, 4):
		var ring_distance = base_distance * ring
		var points_in_ring = 8 * ring
		
		for i in points_in_ring:
			var angle = (i * TAU) / points_in_ring
			var explore_pos = global_position + Vector2(cos(angle), sin(angle)) * ring_distance
			
			if _is_point_in_polygon(explore_pos, system.bounds_polygon) and \
			   not system._is_circle_position_unsafe(explore_pos, agent_radius):
				exploration_points.append(explore_pos)
	
	# Try each exploration point
	for explore_pos in exploration_points:
		if _internal_find_path_to(explore_pos):
			print("Found exploration path to: ", explore_pos)
			# After reaching exploration point, try original target again
			target_position = target_position  # Keep original target for later
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

func _is_immediate_path_valid() -> bool:
	"""Check if the immediate path ahead is valid - Enhanced"""
	if not system or current_path.is_empty() or path_index >= current_path.size():
		return false
	
	# Check current position safety
	if system._is_circle_position_unsafe(global_position, agent_radius):
		print("Current position is unsafe!")
		return false
	
	# Check next few waypoints and paths to them
	var check_count = min(validation_lookahead, current_path.size() - path_index)
	
	for i in range(path_index, path_index + check_count):
		var waypoint = current_path[i]
		
		# Check if waypoint is safe
		if system._is_circle_position_unsafe(waypoint, agent_radius):
			print("Waypoint ", i, " is unsafe: ", waypoint)
			return false
		
		# Check path to waypoint
		if i == path_index:
			# Check path from current position to next waypoint
			if not system._is_safe_circle_path(global_position, waypoint, agent_radius):
				print("Path to current waypoint is unsafe")
				return false
		elif i > path_index:
			# Check path between waypoints
			if not system._is_safe_circle_path(current_path[i-1], waypoint, agent_radius):
				print("Path between waypoints ", i-1, " and ", i, " is unsafe")
				return false
	
	return true

func _attempt_path_recalculation() -> bool:
	"""Attempt to recalculate the path with enhanced strategies"""
	var current_time = Time.get_time_dict_from_system().get("second", 0) as float
	if current_time - last_recalc_time < recalc_cooldown:
		return false
	
	last_recalc_time = current_time
	
	# Try multiple target strategies in order
	var targets_to_try = _get_recalculation_targets()
	
	for target_data in targets_to_try:
		var target = target_data.position
		var strategy = target_data.strategy
		
		print("Trying ", strategy, " to: ", target)
		
		# Force grid update first
		if system and system.is_grid_dirty():
			system.force_grid_update()
		
		# Store current state
		var old_path = current_path.duplicate()
		var old_index = path_index
		var was_moving = is_moving
		
		# Try pathfinding to this target
		if _internal_find_path_to(target):
			print("Successfully found alternative path using ", strategy)
			path_recalculated.emit()
			consecutive_failed_recalcs = 0
			return true
		else:
			# Restore state for next attempt
			current_path = old_path
			path_index = old_index
			is_moving = was_moving
	
	# All strategies failed
	consecutive_failed_recalcs += 1
	print("All recalculation strategies failed (attempt ", consecutive_failed_recalcs, "/", max_failed_recalcs, ")")
	
	# Try partial path continuation as last resort
	if consecutive_failed_recalcs < max_failed_recalcs:
		return _try_partial_path_continuation()
	
	return false

func _try_partial_path_continuation() -> bool:
	"""Try to continue with remaining valid path segments"""
	if current_path.is_empty() or path_index >= current_path.size():
		return false
	
	var valid_segments = _extract_valid_path_segments(current_path, path_index)
	if valid_segments.size() >= 2:
		current_path = valid_segments
		path_index = 0
		print("Continuing with ", valid_segments.size(), " valid path segments")
		return true
	
	return false	

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

func _get_recalculation_targets() -> Array:
	"""Get list of targets to try for recalculation, ordered by preference"""
	var targets = []
	var original_target = target_position
	
	# Strategy 1: Original target (in case obstacle moved away)
	targets.append({
		"position": original_target,
		"strategy": "original_target"
	})
	
	# Strategy 2: Current movement target (immediate waypoint)
	if current_path.size() > path_index:
		targets.append({
			"position": current_path[path_index],
			"strategy": "current_waypoint"
		})
	
	# Strategy 3: Next few waypoints
	for i in range(path_index + 1, min(path_index + 4, current_path.size())):
		targets.append({
			"position": current_path[i],
			"strategy": "waypoint_" + str(i)
		})
	
	# Strategy 4: Nearby safe positions around original target
	var nearby_positions = _generate_nearby_safe_positions(original_target, 50.0, 8)
	for pos in nearby_positions:
		targets.append({
			"position": pos,
			"strategy": "nearby_safe"
		})
	
	# Strategy 5: Wider search around original target
	var wider_positions = _generate_nearby_safe_positions(original_target, 100.0, 12)
	for pos in wider_positions:
		targets.append({
			"position": pos,
			"strategy": "wider_search"
		})
	
	return targets

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

func _try_alternative_pathfinding_strategies():
	"""Enhanced alternative pathfinding with more aggressive strategies"""
	print("Trying enhanced alternative pathfinding strategies...")
	
	# Reset failure count for fresh attempts
	consecutive_failed_recalcs = 0
	
	# Strategy 1: Try multiple fallback targets with wider search
	var fallback_targets = _generate_enhanced_fallback_targets()
	
	for target_data in fallback_targets:
		var target = target_data.position
		var strategy = target_data.strategy
		
		print("Trying ", strategy, ": ", target)
		if _internal_find_path_to(target):
			print("Found alternative path using ", strategy)
			return
	
	# Strategy 2: Try pathfinding to any reachable grid point
	if _try_pathfind_to_any_reachable_point():
		return
	
	# Strategy 3: Temporary pause and retry
	print("All strategies exhausted - pausing and retrying")
	_pause_for_obstacle_movement()

func _try_pathfind_to_any_reachable_point() -> bool:
	"""Try to pathfind to any reachable grid point as emergency movement"""
	if not system:
		return false
	
	print("Trying emergency pathfinding to any reachable point")
	
	# Get all clear grid points
	var clear_points = []
	for grid_pos in system.grid.keys():
		if system.grid[grid_pos] and not system._is_circle_position_unsafe(grid_pos, agent_radius):
			clear_points.append(grid_pos)
	
	# Sort by distance and try closest ones first
	clear_points.sort_custom(func(a, b): return global_position.distance_squared_to(a) < global_position.distance_squared_to(b))
	
	# Try up to 20 closest points
	var max_attempts = min(20, clear_points.size())
	for i in max_attempts:
		var test_target = clear_points[i]
		if _internal_find_path_to(test_target):
			print("Found emergency path to grid point: ", test_target)
			# Update target_position to this emergency target
			target_position = test_target
			return true
	
	return false
	

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

func _generate_enhanced_fallback_targets() -> Array:
	"""Generate enhanced fallback targets with multiple strategies"""
	var targets = []
	var original_target = target_position
	
	# Multiple radii and denser sampling
	var radii = [30.0, 60.0, 100.0, 150.0, 200.0]
	var angle_counts = [8, 12, 16, 20, 24]
	
	for radius_idx in radii.size():
		var radius = radii[radius_idx]
		var angle_count = angle_counts[radius_idx]
		
		for i in angle_count:
			var angle = (i * TAU) / angle_count
			var test_pos = original_target + Vector2(cos(angle), sin(angle)) * radius
			
			# Check if position is valid before adding
			if _is_point_in_polygon(test_pos, system.bounds_polygon):
				targets.append({
					"position": test_pos,
					"strategy": "fallback_r" + str(radius)
				})
	
	# Add random exploration points
	for i in 10:
		var bounds = system._get_bounds_rect()
		var random_pos = Vector2(
			randf_range(bounds.position.x, bounds.position.x + bounds.size.x),
			randf_range(bounds.position.y, bounds.position.y + bounds.size.y)
		)
		
		if _is_point_in_polygon(random_pos, system.bounds_polygon):
			targets.append({
				"position": random_pos,
				"strategy": "random_exploration"
			})
	
	# Sort by distance to current position (closer first)
	targets.sort_custom(func(a, b): return global_position.distance_squared_to(a.position) < global_position.distance_squared_to(b.position))
	
	return targets

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
	"""Monitor for stuck situations and handle recovery"""
	last_positions.append(global_position)
	if last_positions.size() > 10:
		last_positions.pop_front()
	
	if last_positions.size() < 5:
		return
	
	var recent_movement = last_positions[-1].distance_to(last_positions[0])
	
	if recent_movement < stuck_threshold and not is_unsticking:
		stuck_timer += delta
		if stuck_timer >= stuck_time_threshold:
			_handle_stuck_situation()
	else:
		if stuck_timer > 0:
			stuck_timer = 0.0
			if is_unsticking:
				is_unsticking = false
				agent_unstuck.emit()
				print("Agent successfully unstuck")

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
	return _attempt_path_recalculation()

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
	"""Enhanced pathfinding with better error handling"""
	if not system:
		print("No pathfinding system available")
		return false
	
	print("Pathfinder requesting path to: ", destination)
	
	# Try direct pathfinding first
	var path = system.find_path_for_circle(global_position, destination, agent_radius)
	
	if path.is_empty():
		print("Direct pathfinding failed, trying alternative strategies...")
		
		# Try finding path to nearby safe positions around destination
		var nearby_targets = _generate_nearby_safe_positions(destination, 50.0, 12)
		
		for nearby_target in nearby_targets:
			path = system.find_path_for_circle(global_position, nearby_target, agent_radius)
			if not path.is_empty():
				print("Found path to nearby target: ", nearby_target)
				destination = nearby_target  # Update destination to reachable target
				break
		
		# If still no path, try from nearby safe starting positions
		if path.is_empty():
			var safe_starts = _generate_nearby_safe_positions(global_position, 30.0, 8)
			
			for safe_start in safe_starts:
				path = system.find_path_for_circle(safe_start, destination, agent_radius)
				if not path.is_empty():
					print("Found path from alternative start: ", safe_start)
					# Insert movement to safe start position
					path.insert(0, global_position)
					break
	
	if path.is_empty():
		print("All pathfinding strategies failed")
		path_blocked.emit()
		return false
	
	current_path = path
	target_position = destination
	path_index = 0
	is_moving = true
	
	# Reset all state for fresh start
	stuck_timer = 0.0
	is_unsticking = false
	last_positions.clear()
	path_validation_timer = 0.0
	last_path_hash = _calculate_path_hash(path)
	consecutive_failed_recalcs = 0
	
	print("Pathfinder: Path found with ", path.size(), " waypoints")
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
	"""Enhanced collision avoidance with better fallback options"""
	var direction_to_target = (target - global_position).normalized()
	
	# Try sliding along obstacle edges
	var slide_directions = [
		Vector2(-direction_to_target.y, direction_to_target.x),  # Perpendicular left
		Vector2(direction_to_target.y, -direction_to_target.x),  # Perpendicular right
		direction_to_target.rotated(PI * 0.25),  # 45 degrees
		direction_to_target.rotated(-PI * 0.25), # -45 degrees
		direction_to_target.rotated(PI * 0.5),   # 90 degrees
		direction_to_target.rotated(-PI * 0.5)   # -90 degrees
	]
	
	# Try each sliding direction
	for slide_dir in slide_directions:
		var slide_movement = slide_dir * movement_speed * delta * 0.6
		var test_position = global_position + slide_movement
		
		if system and not system._is_circle_position_unsafe(test_position, agent_radius):
			global_position = test_position
			print("Applied collision avoidance sliding: ", slide_dir)
			
			# After successful slide, try to recalculate path
			if randf() < 0.3:  # 30% chance to recalculate after slide
				call_deferred("_attempt_path_recalculation")
			
			return
	
	# If sliding failed, try smaller forward movement
	var reduced_movement = direction_to_target * movement_speed * delta * 0.2
	var test_position = global_position + reduced_movement
	
	if system and not system._is_circle_position_unsafe(test_position, agent_radius):
		global_position = test_position
		print("Applied reduced forward movement")
	else:
		# Instead of immediately calling stuck handler, try one more recalculation
		if consecutive_failed_recalcs < max_failed_recalcs:
			call_deferred("_attempt_path_recalculation")
		else:
			_handle_stuck_situation()

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
	
	_attempt_path_recalculation()

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
