@tool
extends Node2D
class_name PathfinderSystem

@export var bounds_polygon: PackedVector2Array = PackedVector2Array([
	Vector2(-500, -500),
	Vector2(500, -500),
	Vector2(500, 500),
	Vector2(-500, 500)
])

@export var grid_size: float = 25.0
@export var dynamic_update_rate: float = 0.1
@export var auto_invalidate_paths: bool = true
@export var pathfinders: Array[Pathfinder] = []
@export var obstacles: Array[PathfinderObstacle] = []

var obstacle_validity_cache: Dictionary = {}
var validity_cache_timer: float = 0.0
var validity_cache_interval: float = 0.5  # Check validity every 0.5 seconds
var pending_static_changes: Array[PathfinderObstacle] = []
var batch_timer: float = 0.0
var batch_interval: float = 0.1  # Process batches every 0.1 seconds

var grid: Dictionary = {}
var dynamic_obstacles: Array[PathfinderObstacle] = []

var grid_dirty: bool = false
var last_grid_update: float = 0.0
var path_invalidation_timer: float = 0.0

# Pathfinding components
var open_set: Array[PathNode] = []
var closed_set: Dictionary = {}
var came_from: Dictionary = {}

class PathNode:
	var position: Vector2
	var g_score: float
	var f_score: float
	var h_score: float
	
	func _init(pos: Vector2, g: float = 0.0, h: float = 0.0):
		position = pos
		g_score = g
		h_score = h
		f_score = g + h

func _ready():
	if not Engine.is_editor_hint():
		_initialize_system()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_dynamic_system(delta)

func _update_dynamic_system(delta):
	last_grid_update += delta
	path_invalidation_timer += delta
	validity_cache_timer += delta
	batch_timer += delta
	
	# Update validity cache periodically
	if validity_cache_timer >= validity_cache_interval:
		_update_validity_cache()
		validity_cache_timer = 0.0
	
	# Process batched static/dynamic changes
	if batch_timer >= batch_interval and not pending_static_changes.is_empty():
		_process_batched_static_changes()
		batch_timer = 0.0
	
	# Clean up invalid obstacles lazily
	_lazy_cleanup_obstacles()
	
	var should_update_grid = grid_dirty and last_grid_update >= dynamic_update_rate
	var should_invalidate_paths = auto_invalidate_paths and path_invalidation_timer >= dynamic_update_rate * 2
	
	if should_update_grid:
		_update_grid_for_dynamic_obstacles()
		grid_dirty = false
		last_grid_update = 0.0
	
	if should_invalidate_paths and not _get_valid_dynamic_obstacles().is_empty():
		_invalidate_affected_paths()
		path_invalidation_timer = 0.0

func _update_validity_cache():
	"""Update cached validity for all obstacles"""
	obstacle_validity_cache.clear()
	
	for obstacle in obstacles:
		obstacle_validity_cache[obstacle] = is_instance_valid(obstacle)
	
	for obstacle in dynamic_obstacles:
		if obstacle not in obstacle_validity_cache:
			obstacle_validity_cache[obstacle] = is_instance_valid(obstacle)

func _is_obstacle_valid_cached(obstacle: PathfinderObstacle) -> bool:
	"""Get cached validity or fallback to real check"""
	if obstacle in obstacle_validity_cache:
		return obstacle_validity_cache[obstacle]
	else:
		# Fallback for new obstacles not yet cached
		return is_instance_valid(obstacle)

func _lazy_cleanup_obstacles():
	"""Remove invalid obstacles only when needed, not immediately"""
	# Only clean if we have cached validity info
	if obstacle_validity_cache.is_empty():
		return
	
	# Clean up main obstacles array
	var initial_size = obstacles.size()
	obstacles = obstacles.filter(func(o): return _is_obstacle_valid_cached(o))
	
	# Clean up dynamic obstacles array
	dynamic_obstacles = dynamic_obstacles.filter(func(o): return _is_obstacle_valid_cached(o))
	
	# Log cleanup if significant
	if obstacles.size() < initial_size - 2:  # Only log if more than 2 removed
		print("Cleaned up ", initial_size - obstacles.size(), " invalid obstacles")

func _get_valid_dynamic_obstacles() -> Array[PathfinderObstacle]:
	"""Get filtered valid dynamic obstacles (cached)"""
	var valid_dynamic: Array[PathfinderObstacle] = []
	
	for obstacle in dynamic_obstacles:
		if _is_obstacle_valid_cached(obstacle) and not obstacle.is_static:
			valid_dynamic.append(obstacle)
	
	return valid_dynamic

func _process_batched_static_changes():
	"""Process multiple static/dynamic state changes in one batch"""
	print("Processing ", pending_static_changes.size(), " batched static changes")
	
	var became_static = 0
	var became_dynamic = 0
	
	for obstacle in pending_static_changes:
		if not _is_obstacle_valid_cached(obstacle):
			continue
			
		if obstacle.is_static:
			# Became static - remove from dynamic list
			if obstacle in dynamic_obstacles:
				dynamic_obstacles.erase(obstacle)
				became_static += 1
				if obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
					obstacle.obstacle_changed.disconnect(_on_obstacle_changed)
		else:
			# Became dynamic - add to dynamic list
			if obstacle not in dynamic_obstacles:
				dynamic_obstacles.append(obstacle)
				became_dynamic += 1
				if not obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
					obstacle.obstacle_changed.connect(_on_obstacle_changed)
	
	if became_static > 0 or became_dynamic > 0:
		print("Batch processed: ", became_static, " became static, ", became_dynamic, " became dynamic")
		grid_dirty = true  # Trigger grid update after batch
	
	pending_static_changes.clear()

func _initialize_system():
	_register_initial_pathfinders()
	_register_initial_obstacles()
	_build_grid()

func _register_initial_pathfinders() -> void:
	for pathfinder in pathfinders:
		_prepare_registered_pathfinder(pathfinder)

func _register_initial_obstacles() -> void:
	for obstacle in obstacles:
		_prepare_registered_obstacle(obstacle)

func _build_grid():
	grid.clear()
	var bounds = _get_bounds_rect()
	
	var steps_x = int(bounds.size.x / grid_size) + 1
	var steps_y = int(bounds.size.y / grid_size) + 1
	
	for i in steps_x:
		for j in steps_y:
			var x = bounds.position.x + (i * grid_size)
			var y = bounds.position.y + (j * grid_size)
			var pos = Vector2(x, y)
			
			if _is_point_in_polygon(pos, bounds_polygon):
				grid[pos] = _is_grid_point_clear(pos)

func _update_grid_for_dynamic_obstacles():
	print("=== UPDATING GRID FOR DYNAMIC OBSTACLES ===")
	
	# Use cached validation instead of repeated is_instance_valid calls
	var valid_dynamic = _get_valid_dynamic_obstacles()
	
	if valid_dynamic.is_empty():
		print("No valid dynamic obstacles - skipping grid update")
		return
	
	var affected_bounds = _get_dynamic_obstacles_bounds_cached(valid_dynamic)
	print("Affected bounds: ", affected_bounds)
	
	if affected_bounds.size.x <= 0 or affected_bounds.size.y <= 0:
		print("Invalid bounds - skipping grid update")
		return
	
	for grid_pos in grid.keys():
		if affected_bounds.has_point(grid_pos):
			grid[grid_pos] = _is_grid_point_clear(grid_pos)

func _get_dynamic_obstacles_bounds_cached(valid_dynamic: Array[PathfinderObstacle]) -> Rect2:
	"""Get bounds using already-filtered valid dynamic obstacles"""
	if valid_dynamic.is_empty():
		return Rect2()
	
	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)
	
	for obstacle in valid_dynamic:
		var world_poly = obstacle.get_world_polygon()
		for point in world_poly:
			min_pos = min_pos.min(point)
			max_pos = max_pos.max(point)
	
	var buffer = grid_size * 2
	return Rect2(min_pos - Vector2(buffer, buffer), (max_pos - min_pos) + Vector2(buffer * 2, buffer * 2))


# SIMPLIFIED: Get bounds of dynamic obstacles
func _get_dynamic_obstacles_bounds() -> Rect2:
	# Filter dynamic obstacles inline instead of using separate array
	dynamic_obstacles = dynamic_obstacles.filter(func(o): return is_instance_valid(o) and not o.is_static)
	
	if dynamic_obstacles.is_empty():
		return Rect2()
	
	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)
	
	for obstacle in dynamic_obstacles:
		var world_poly = obstacle.get_world_polygon()
		for point in world_poly:
			min_pos = min_pos.min(point)
			max_pos = max_pos.max(point)
	
	var buffer = grid_size * 2
	return Rect2(min_pos - Vector2(buffer, buffer), (max_pos - min_pos) + Vector2(buffer * 2, buffer * 2))

func _is_grid_point_clear(pos: Vector2) -> bool:
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.is_point_inside(pos):
			return false
	return true

func _invalidate_affected_paths():
	for pathfinder in pathfinders:
		if is_instance_valid(pathfinder) and pathfinder.is_moving and not pathfinder.is_path_valid():
			pathfinder.recalculate_path()

func register_obstacle(obstacle: PathfinderObstacle):
	if obstacle in obstacles:
		return
	
	obstacles.append(obstacle)
	
	_prepare_registered_obstacle(obstacle)

func _prepare_registered_obstacle(obstacle: PathfinderObstacle):
	obstacle.system = self
	if not obstacle.is_static and obstacle not in dynamic_obstacles:
		dynamic_obstacles.append(obstacle)
	if not obstacle.is_static:
		if not obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
			obstacle.obstacle_changed.connect(_on_obstacle_changed)
	if not obstacle.static_state_changed.is_connected(_on_obstacle_static_changed):
		obstacle.static_state_changed.connect(_on_obstacle_static_changed.bind(obstacle))

func _on_obstacle_static_changed(is_now_static: bool, obstacle: PathfinderObstacle):
	"""Queue static/dynamic state changes for batch processing"""
	if obstacle not in pending_static_changes:
		pending_static_changes.append(obstacle)
	
	# For immediate critical cases, still process right away
	if pending_static_changes.size() > 10:  # Prevent queue from getting too large
		_process_batched_static_changes()

func unregister_obstacle(obstacle: PathfinderObstacle):
	obstacles.erase(obstacle)
	dynamic_obstacles.erase(obstacle)
	obstacle.system = null
	
	if obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
		obstacle.obstacle_changed.disconnect(_on_obstacle_changed)
	if obstacle.static_state_changed.is_connected(_on_obstacle_static_changed):
		obstacle.static_state_changed.disconnect(_on_obstacle_static_changed)

func register_pathfinder(pathfinder: Pathfinder):
	if pathfinder not in pathfinders:
		pathfinders.append(pathfinder)
	
	_prepare_registered_pathfinder(pathfinder)

func _prepare_registered_pathfinder(pathfinder: Pathfinder):
	pathfinder.system = self

func unregister_pathfinder(pathfinder: Pathfinder):
	pathfinders.erase(pathfinder)
	pathfinder.system = null

func find_path_for_circle(start: Vector2, end: Vector2, radius: float, buffer: float = 2.0) -> PackedVector2Array:
	print("=== PATHFINDING REQUEST ===")
	print("Start: ", start, " End: ", end, " Radius: ", radius, " Buffer: ", buffer)
	print("Grid dirty: ", grid_dirty)
	print("Total obstacles: ", obstacles.size())
	
	# Log all obstacle positions and states
	for i in range(obstacles.size()):
		var obs = obstacles[i]
		if is_instance_valid(obs):
			print("Obstacle ", i, ": pos=", obs.global_position, " static=", obs.is_static, " poly=", obs.get_world_polygon())
		else:
			print("Obstacle ", i, ": INVALID")
	
	if grid_dirty:
		print("Updating grid for dynamic obstacles...")
		_update_grid_for_dynamic_obstacles()
		grid_dirty = false
		last_grid_update = 0.0
	
	if _is_safe_circle_path(start, end, radius, buffer):
		print("Using direct path")
		return PackedVector2Array([start, end])
	
	var start_grid = _find_safe_circle_position(start, radius, buffer)
	var end_grid = _find_safe_circle_position(end, radius, buffer)
	
	print("Start grid pos: ", start_grid, " (safe: ", start_grid != Vector2.INF, ")")
	print("End grid pos: ", end_grid, " (safe: ", end_grid != Vector2.INF, ")")
	
	if start_grid == Vector2.INF or end_grid == Vector2.INF:
		print("No safe grid positions found - PATH BLOCKED")
		return PackedVector2Array()
	
	var path = _a_star_pathfind_circle(start_grid, end_grid, radius, buffer)
	print("A* result: ", path.size(), " waypoints")
	
	if path.size() > 2:
		path = _smooth_circle_path(path, radius, buffer)
		print("Smoothed to: ", path.size(), " waypoints")
	
	print("=== END PATHFINDING REQUEST ===")
	return path

func _get_bounds_rect() -> Rect2:
	if bounds_polygon.is_empty():
		return Rect2(-500, -500, 1000, 1000)
	
	var min_x = bounds_polygon[0].x
	var max_x = bounds_polygon[0].x
	var min_y = bounds_polygon[0].y
	var max_y = bounds_polygon[0].y
	
	for point in bounds_polygon:
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)
	
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

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

func _is_safe_circle_path(start: Vector2, end: Vector2, radius: float, buffer: float) -> bool:
	var distance = start.distance_to(end)
	var samples = max(int(distance / (grid_size * 0.5)), 8)
	
	for i in samples + 1:
		var t = float(i) / float(samples)
		var test_pos = start.lerp(end, t)
		
		if _is_circle_position_unsafe(test_pos, radius, buffer):
			return false
	
	return true

func _is_circle_position_unsafe(pos: Vector2, radius: float, buffer: float) -> bool:
	var total_radius = radius + buffer
	
	# Must be within bounds
	if not _is_point_in_polygon(pos, bounds_polygon):
		return true
	
	# Check distance to all obstacles
	for obstacle in obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var world_poly = obstacle.get_world_polygon()
		if world_poly.is_empty():
			continue
			
		var distance_to_obstacle = _distance_point_to_polygon(pos, world_poly)
		
		# Add small tolerance to prevent edge cases
		var safety_margin = 0.5
		if distance_to_obstacle < (total_radius - safety_margin):
			return true
	
	return false

func _distance_point_to_polygon(point: Vector2, polygon: PackedVector2Array) -> float:
	if polygon.is_empty():
		return INF
	
	if _is_point_in_polygon(point, polygon):
		return 0.0
	
	var min_distance = INF
	
	for i in polygon.size():
		var edge_start = polygon[i]
		var edge_end = polygon[(i + 1) % polygon.size()]
		var distance = _distance_point_to_line_segment(point, edge_start, edge_end)
		min_distance = min(min_distance, distance)
	
	return min_distance

func _distance_point_to_line_segment(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	
	var line_len_sq = line_vec.length_squared()
	if line_len_sq < 0.001:
		return point.distance_to(line_start)
	
	var t = clamp(point_vec.dot(line_vec) / line_len_sq, 0.0, 1.0)
	var projection = line_start + t * line_vec
	
	return point.distance_to(projection)

func _find_safe_circle_position(pos: Vector2, radius: float, buffer: float) -> Vector2:
	# First try the exact position
	if not _is_circle_position_unsafe(pos, radius, buffer):
		return pos
	
	# Try snapped grid position
	var snapped = _snap_to_grid(pos)
	if not _is_circle_position_unsafe(snapped, radius, buffer):
		return snapped
	
	# For larger agents or fine grids, search in expanding circles
	var search_step = min(grid_size * 0.5, radius * 0.5)  # Smaller steps for precision
	var max_search_radius = max(grid_size * 12, radius * 6)  # Scale with agent size
	
	# Try positions in expanding circles around target
	for search_radius in range(int(search_step), int(max_search_radius), int(search_step)):
		var angle_step = PI / 8  # 8 directions per circle
		
		for angle in range(0, int(TAU / angle_step)):
			var test_angle = angle * angle_step
			var offset = Vector2(cos(test_angle), sin(test_angle)) * search_radius
			var test_pos = pos + offset
			
			# Must be within bounds and not unsafe
			if _is_point_in_polygon(test_pos, bounds_polygon) and not _is_circle_position_unsafe(test_pos, radius, buffer):
				return test_pos
	
	# Final fallback: try grid points in expanded area
	for grid_pos in grid.keys():
		if pos.distance_to(grid_pos) <= max_search_radius:
			if not _is_circle_position_unsafe(grid_pos, radius, buffer):
				return grid_pos
	
	return Vector2.INF

func _snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		round(pos.x / grid_size) * grid_size,
		round(pos.y / grid_size) * grid_size
	)

func _a_star_pathfind_circle(start: Vector2, goal: Vector2, radius: float, buffer: float) -> PackedVector2Array:
	open_set.clear()
	closed_set.clear()
	came_from.clear()
	
	var start_node = PathNode.new(start, 0.0, _heuristic(start, goal))
	open_set.append(start_node)
	
	var iterations = 0
	var max_iterations = 3000  # Increased for better pathfinding
	
	# Dynamic goal tolerance based on agent size
	var goal_tolerance = max(grid_size * 0.7, radius * 0.5)
	
	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1
		
		# Find lowest f_score
		var current_idx = 0
		for i in range(1, open_set.size()):
			if open_set[i].f_score < open_set[current_idx].f_score:
				current_idx = i
		
		var current = open_set[current_idx]
		open_set.remove_at(current_idx)
		
		# Check if we reached the goal (with tolerance)
		if current.position.distance_to(goal) < goal_tolerance:
			return _reconstruct_path(came_from, current.position, start)
		
		closed_set[current.position] = true
		
		# Get neighbors with dynamic step size
		var neighbors = _get_adaptive_neighbors(current.position, radius, buffer)
		
		for neighbor_pos in neighbors:
			if closed_set.has(neighbor_pos):
				continue
			
			if _is_circle_position_unsafe(neighbor_pos, radius, buffer):
				continue
			
			if not _is_safe_circle_path(current.position, neighbor_pos, radius, buffer):
				continue
			
			var movement_cost = current.position.distance_to(neighbor_pos)
			var tentative_g = current.g_score + movement_cost
			
			var existing_node = null
			for node in open_set:
				if node.position.distance_to(neighbor_pos) < grid_size * 0.3:  # Close enough
					existing_node = node
					break
			
			if existing_node == null:
				var new_node = PathNode.new(neighbor_pos, tentative_g, _heuristic(neighbor_pos, goal))
				open_set.append(new_node)
				came_from[neighbor_pos] = current.position
			elif tentative_g < existing_node.g_score:
				existing_node.g_score = tentative_g
				existing_node.f_score = tentative_g + existing_node.h_score
				came_from[neighbor_pos] = current.position
	
	return PackedVector2Array()


func _get_adaptive_neighbors(pos: Vector2, radius: float, buffer: float) -> Array[Vector2]:
	var neighbors: Array[Vector2] = []
	
	# Use smaller steps for larger agents to find more precise paths
	var step_size = grid_size
	if radius > grid_size * 0.7:
		step_size = max(grid_size * 0.5, radius * 0.8)  # Adaptive step size
	
	# Standard 8-direction movement
	var directions = [
		Vector2(step_size, 0), Vector2(-step_size, 0),
		Vector2(0, step_size), Vector2(0, -step_size),
		Vector2(step_size, step_size), Vector2(-step_size, -step_size),
		Vector2(step_size, -step_size), Vector2(-step_size, step_size)
	]
	
	# For larger agents, also try half-steps to find tighter passages
	if radius > grid_size * 0.5:
		var half_step = step_size * 0.5
		directions.append_array([
			Vector2(half_step, 0), Vector2(-half_step, 0),
			Vector2(0, half_step), Vector2(0, -half_step)
		])
	
	for direction in directions:
		var neighbor = pos + direction
		
		# Check if within bounds
		if _is_point_in_polygon(neighbor, bounds_polygon):
			neighbors.append(neighbor)
	
	return neighbors

func _heuristic(pos: Vector2, goal: Vector2) -> float:
	return pos.distance_to(goal)

func _smooth_circle_path(path: PackedVector2Array, radius: float, buffer: float) -> PackedVector2Array:
	if path.size() <= 2:
		return path
	
	var smoothed: PackedVector2Array = []
	smoothed.append(path[0])
	
	var current_index = 0
	
	while current_index < path.size() - 1:
		var farthest_safe = current_index + 1
		
		for i in range(current_index + 2, path.size()):
			if _is_safe_circle_path(path[current_index], path[i], radius, buffer):
				farthest_safe = i
			else:
				break
		
		current_index = farthest_safe
		smoothed.append(path[current_index])
	
	return smoothed

func _reconstruct_path(came_from_dict: Dictionary, current: Vector2, start: Vector2) -> PackedVector2Array:
	var path: PackedVector2Array = []
	path.append(current)
	
	while came_from_dict.has(current) and current != start:
		current = came_from_dict[current]
		path.append(current)
	
	path.reverse()
	return path



# Utility functions
func get_dynamic_obstacle_count() -> int:
	return _get_valid_dynamic_obstacles().size()


func is_grid_dirty() -> bool:
	return grid_dirty

func force_grid_update():
	if dynamic_obstacles.size() > 0:
		_update_grid_for_dynamic_obstacles()
		grid_dirty = false
		last_grid_update = 0.0

# SIMPLIFIED: Single obstacle change handler
func _on_obstacle_changed():
	print("=== OBSTACLE CHANGED EVENT ===")
	
	# Find which obstacle actually changed by checking all dynamic obstacles
	var changed_obstacle = null
	for obstacle in dynamic_obstacles:
		if is_instance_valid(obstacle) and obstacle._has_changed():
			changed_obstacle = obstacle
			break
	
	if not changed_obstacle:
		print("No changed obstacle found - skipping update")
		return
	
	print("Changed obstacle at: ", changed_obstacle.global_position)
	
	# Update grid only around the changed obstacle
	_update_grid_around_obstacle(changed_obstacle)
	
	# Only invalidate paths that actually intersect with this obstacle
	var affected_pathfinders = _get_pathfinders_affected_by_obstacle(changed_obstacle)
	print("Affecting ", affected_pathfinders.size(), " pathfinders")
	
	for pathfinder in affected_pathfinders:
		if pathfinder.is_moving:
			print("Invalidating path for pathfinder at: ", pathfinder.global_position)
			pathfinder.consecutive_failed_recalcs = 0
			pathfinder.call_deferred("_recalculate_or_find_alternative")
	
	print("=== END OBSTACLE CHANGED ===")

func _update_grid_around_obstacle(obstacle: PathfinderObstacle):
	"""Update grid points around a specific obstacle only"""
	var world_poly = obstacle.get_world_polygon()
	var obstacle_bounds = _get_polygon_bounds(world_poly)
	
	# Expand bounds for agent clearance
	obstacle_bounds = obstacle_bounds.grow(grid_size * 3)
	
	var updated_count = 0
	for grid_pos in grid.keys():
		if obstacle_bounds.has_point(grid_pos):
			var old_value = grid[grid_pos]
			var new_value = _is_grid_point_clear(grid_pos)
			if old_value != new_value:
				grid[grid_pos] = new_value
				updated_count += 1
	
	print("Updated ", updated_count, " grid points around obstacle")

func _find_closest_safe_point(unsafe_pos: Vector2, radius: float, buffer: float) -> Vector2:
	"""Find the closest safe point outside all obstacles for a given unsafe position"""
	
	# First, find which obstacle(s) contain this point
	var containing_obstacles: Array[PathfinderObstacle] = []
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.is_point_inside(unsafe_pos):
			containing_obstacles.append(obstacle)
	
	if containing_obstacles.is_empty():
		# Point is not actually inside an obstacle, check if it's just too close
		print("Point not inside obstacle, finding safe position nearby...")
		return _find_safe_circle_position(unsafe_pos, radius, buffer)
	
	print("Point is inside ", containing_obstacles.size(), " obstacle(s)")
	
	# For each containing obstacle, find multiple candidate points
	var candidates: Array[Vector2] = []
	
	for obstacle in containing_obstacles:
		var safe_pos = _find_closest_point_outside_obstacle(unsafe_pos, obstacle, radius, buffer)
		if safe_pos != Vector2.INF:
			candidates.append(safe_pos)
		
		# Also try finding safe points in cardinal directions from obstacle edges
		var world_poly = obstacle.get_world_polygon()
		var poly_center = _get_polygon_center(world_poly)
		var directions = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
		
		for direction in directions:
			var test_distance = (radius + buffer + 25.0)  # Generous distance
			var candidate = unsafe_pos + direction * test_distance
			
			if _is_point_in_polygon(candidate, bounds_polygon) and \
			   not _is_circle_position_unsafe(candidate, radius, buffer):
				candidates.append(candidate)
	
	# Choose the closest valid candidate
	if not candidates.is_empty():
		var best_candidate = candidates[0]
		var best_distance = unsafe_pos.distance_to(best_candidate)
		
		for candidate in candidates:
			var distance = unsafe_pos.distance_to(candidate)
			if distance < best_distance:
				best_distance = distance
				best_candidate = candidate
		
		print("Selected best candidate at distance: ", best_distance)
		return best_candidate
	
	# Fallback: search in expanding circles with larger steps
	print("Using enhanced fallback search method...")
	var search_step = max(grid_size, radius + buffer + 10.0)  # Larger search steps
	var max_search_radius = max(grid_size * 15, radius * 10)  # Expanded search area
	
	# Try positions in expanding circles around target
	for search_radius in range(int(search_step), int(max_search_radius), int(search_step)):
		var angle_step = PI / 6  # 12 directions per circle (more directions)
		
		for angle in range(0, int(TAU / angle_step)):
			var test_angle = angle * angle_step
			var offset = Vector2(cos(test_angle), sin(test_angle)) * search_radius
			var test_pos = unsafe_pos + offset
			
			# Must be within bounds and not unsafe
			if _is_point_in_polygon(test_pos, bounds_polygon) and \
			   not _is_circle_position_unsafe(test_pos, radius, buffer):
				print("Fallback found safe point at: ", test_pos)
				return test_pos
	
	print("Could not find any safe point!")
	return Vector2.INF

func _find_closest_point_outside_obstacle(point: Vector2, obstacle: PathfinderObstacle, radius: float, buffer: float) -> Vector2:
	"""Find closest point outside a specific obstacle with better clearance"""
	var world_poly = obstacle.get_world_polygon()
	if world_poly.is_empty():
		return Vector2.INF
	
	var closest_point = Vector2.INF
	var closest_distance = INF
	
	# Increase clearance distance significantly for better pathfinding success
	var base_clearance = radius + buffer + 15.0  # Increased base clearance
	var safety_margin = 10.0  # Additional safety margin
	
	# Check each edge of the polygon
	for i in world_poly.size():
		var edge_start = world_poly[i]
		var edge_end = world_poly[(i + 1) % world_poly.size()]
		
		# Find closest point on this edge
		var edge_point = _closest_point_on_line_segment(point, edge_start, edge_end)
		
		# Calculate outward direction from obstacle
		var direction = (point - edge_point).normalized()
		if direction.length() < 0.01:  # Handle case where point is exactly on edge
			# Use edge normal instead
			var edge_vector = (edge_end - edge_start).normalized()
			direction = Vector2(-edge_vector.y, edge_vector.x)  # Perpendicular (outward)
			
			# Determine which side is "outward" by testing
			var test_point1 = edge_point + direction * 5.0
			var test_point2 = edge_point - direction * 5.0
			
			if _is_point_in_polygon(test_point1, world_poly):
				direction = -direction  # Flip if we picked the wrong direction
		
		# Try multiple clearance distances for robustness
		var clearance_distances = [
			base_clearance + safety_margin,
			base_clearance + safety_margin * 2,
			base_clearance + safety_margin * 3
		]
		
		for clearance_distance in clearance_distances:
			var safe_candidate = edge_point + direction * clearance_distance
			
			# Verify this candidate is good
			if _is_point_in_polygon(safe_candidate, bounds_polygon) and \
			   not _is_circle_position_unsafe(safe_candidate, radius, buffer):
				var distance = point.distance_to(safe_candidate)
				if distance < closest_distance:
					closest_distance = distance
					closest_point = safe_candidate
					break  # Found a good point, stop trying further distances
	
	# If no edge-based solution worked, try radial approach with multiple distances
	if closest_point == Vector2.INF:
		print("Edge-based approach failed, trying radial approach...")
		var poly_center = _get_polygon_center(world_poly)
		var direction = (point - poly_center).normalized()
		
		# Try progressively larger distances
		var test_distances = [
			base_clearance + safety_margin,
			base_clearance + safety_margin * 2,
			base_clearance + safety_margin * 3,
			base_clearance + safety_margin * 4
		]
		
		for dist in test_distances:
			var candidate = point + direction * dist
			if _is_point_in_polygon(candidate, bounds_polygon) and \
			   not _is_circle_position_unsafe(candidate, radius, buffer):
				print("Radial approach found safe point at distance: ", dist)
				return candidate
		
		# Last resort: try 8 cardinal directions from the point
		print("Trying cardinal directions as last resort...")
		var directions = [
			Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
			Vector2(0.707, 0.707), Vector2(-0.707, 0.707), 
			Vector2(0.707, -0.707), Vector2(-0.707, -0.707)
		]
		
		for dir in directions:
			for dist in test_distances:
				var candidate = point + dir * dist
				if _is_point_in_polygon(candidate, bounds_polygon) and \
				   not _is_circle_position_unsafe(candidate, radius, buffer):
					print("Cardinal direction found safe point: ", candidate)
					return candidate
	
	return closest_point

func _get_polygon_center(polygon: PackedVector2Array) -> Vector2:
	"""Calculate the center point of a polygon"""
	if polygon.is_empty():
		return Vector2.ZERO
	
	var sum = Vector2.ZERO
	for point in polygon:
		sum += point
	
	return sum / polygon.size()

func _closest_point_on_line_segment(point: Vector2, line_start: Vector2, line_end: Vector2) -> Vector2:
	"""Find the closest point on a line segment to a given point"""
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	
	var line_len_sq = line_vec.length_squared()
	if line_len_sq < 0.001:
		return line_start
	
	var t = clamp(point_vec.dot(line_vec) / line_len_sq, 0.0, 1.0)
	return line_start + t * line_vec

# Add this new function to pathfinder_system.gd (after _update_grid_around_obstacle)
func _get_pathfinders_affected_by_obstacle(obstacle: PathfinderObstacle) -> Array[Pathfinder]:
	"""Get pathfinders whose paths might be affected by this obstacle"""
	var affected: Array[Pathfinder] = []
	var world_poly = obstacle.get_world_polygon()
	var obstacle_bounds = _get_polygon_bounds(world_poly)
	
	# Expand bounds to account for agent sizes
	obstacle_bounds = obstacle_bounds.grow(50.0)  # Conservative expansion
	
	for pathfinder in pathfinders:
		if not is_instance_valid(pathfinder) or not pathfinder.is_moving:
			continue
		
		# Check if pathfinder's current path intersects obstacle area
		var path = pathfinder.get_current_path()
		var path_intersects = false
		
		# Check if any remaining waypoints are in the obstacle area
		for i in range(pathfinder.path_index, path.size()):
			if obstacle_bounds.has_point(path[i]):
				path_intersects = true
				break
		
		# Check if any remaining path segments cross the obstacle area
		if not path_intersects:
			for i in range(pathfinder.path_index, path.size() - 1):
				var segment_start = path[i]
				var segment_end = path[i + 1]
				
				# Create bounding box for this segment
				var segment_bounds = Rect2()
				segment_bounds = segment_bounds.expand(segment_start)
				segment_bounds = segment_bounds.expand(segment_end)
				
				if segment_bounds.intersects(obstacle_bounds):
					path_intersects = true
					break
		
		if path_intersects:
			affected.append(pathfinder)
	
	return affected

func _get_polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	"""Get bounding rectangle of a polygon"""
	if polygon.is_empty():
		return Rect2()
	
	var min_pos = polygon[0]
	var max_pos = polygon[0]
	
	for point in polygon:
		min_pos.x = min(min_pos.x, point.x)
		min_pos.y = min(min_pos.y, point.y)
		max_pos.x = max(max_pos.x, point.x)
		max_pos.y = max(max_pos.y, point.y)
	
	return Rect2(min_pos, max_pos - min_pos)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if bounds_polygon.size() < 3:
		warnings.append("Bounds polygon needs at least 3 points")
	
	if grid_size <= 0:
		warnings.append("Grid size must be greater than 0")
	
	return warnings
