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
@export var agent_buffer: float = 5.0
@export var corner_buffer: float = 8.0
@export var max_corner_angle: float = 120.0

# Dynamic update settings
@export var dynamic_update_rate: float = 0.1  # How often to check for dynamic changes (seconds)
@export var auto_invalidate_paths: bool = true  # Automatically invalidate paths when obstacles change

var grid: Dictionary = {}
var obstacles: Array[PathfinderObstacle] = []
var pathfinders: Array[Pathfinder] = []

# Dynamic tracking
var dynamic_obstacles: Array[PathfinderObstacle] = []
var grid_dirty: bool = false
var last_grid_update: float = 0.0
var path_invalidation_timer: float = 0.0

# Pathfinding algorithm components
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
	add_to_group("pathfinder_systems")
	if not Engine.is_editor_hint():
		_initialize_system()

func _process(delta):
	if Engine.is_editor_hint():
		return
	
	_update_dynamic_system(delta)

func _update_dynamic_system(delta):
	"""Update dynamic obstacle tracking and grid - Enhanced"""
	last_grid_update += delta
	path_invalidation_timer += delta
	
	# More frequent updates when dynamic obstacles are present
	var update_rate = dynamic_update_rate
	if dynamic_obstacles.size() > 0:
		update_rate *= 0.5  # Update twice as often
	
	# Update grid if dirty and enough time has passed
	if grid_dirty and last_grid_update >= update_rate:
		_update_grid_for_dynamic_obstacles()
		grid_dirty = false
		last_grid_update = 0.0
	
	# More frequent path invalidation checks
	var invalidation_rate = update_rate * 1.5
	if auto_invalidate_paths and dynamic_obstacles.size() > 0 and path_invalidation_timer >= invalidation_rate:
		_invalidate_affected_paths()
		path_invalidation_timer = 0.0

func _initialize_system():
	_build_grid()
	_find_and_register_obstacles()
	_find_and_register_pathfinders()
	print("PathfinderSystem initialized with ", grid.size(), " grid points and ", dynamic_obstacles.size(), " dynamic obstacles")

func _find_and_register_obstacles():
	var obstacle_nodes = get_tree().get_nodes_in_group("pathfinder_obstacles")
	for obstacle in obstacle_nodes:
		if obstacle is PathfinderObstacle:
			register_obstacle(obstacle)

func _find_and_register_pathfinders():
	var pathfinder_nodes = get_tree().get_nodes_in_group("pathfinders")
	for pathfinder in pathfinder_nodes:
		if pathfinder is Pathfinder:
			register_pathfinder(pathfinder)

func _build_grid():
	"""Build the initial navigation grid"""
	grid.clear()
	var bounds = _get_bounds_rect()
	print("Building grid with bounds: ", bounds)
	
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
	"""Update grid points affected by dynamic obstacles"""
	if dynamic_obstacles.is_empty():
		return
	
	print("Updating grid for ", dynamic_obstacles.size(), " dynamic obstacles")
	
	# Get affected area
	var affected_bounds = _get_dynamic_obstacles_bounds()
	if affected_bounds.size.x <= 0 or affected_bounds.size.y <= 0:
		return
	
	# Update grid points in affected area
	var updated_count = 0
	for grid_pos in grid.keys():
		if affected_bounds.has_point(grid_pos):
			var old_value = grid[grid_pos]
			var new_value = _is_grid_point_clear(grid_pos)
			if old_value != new_value:
				grid[grid_pos] = new_value
				updated_count += 1
	
	print("Updated ", updated_count, " grid points")

func _get_dynamic_obstacles_bounds() -> Rect2:
	"""Get bounding rectangle of all dynamic obstacles"""
	if dynamic_obstacles.is_empty():
		return Rect2()
	
	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)
	
	for obstacle in dynamic_obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var world_poly = obstacle.get_world_polygon()
		for point in world_poly:
			min_pos.x = min(min_pos.x, point.x)
			min_pos.y = min(min_pos.y, point.y)
			max_pos.x = max(max_pos.x, point.x)
			max_pos.y = max(max_pos.y, point.y)
	
	# Add buffer for agent sizes
	var buffer = grid_size * 3
	min_pos -= Vector2(buffer, buffer)
	max_pos += Vector2(buffer, buffer)
	
	return Rect2(min_pos, max_pos - min_pos)

func _is_grid_point_clear(pos: Vector2) -> bool:
	"""Check if a grid point is clear of all obstacles"""
	# Don't apply agent_buffer here - that's handled in pathfinding
	for obstacle in obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		if obstacle.is_point_inside(pos):
			return false
	
	return true

func _invalidate_affected_paths():
	"""Invalidate paths that might be affected by dynamic obstacle changes"""
	var invalidated_count = 0
	
	for pathfinder in pathfinders:
		if not is_instance_valid(pathfinder) or not pathfinder.is_moving:
			continue
		
		# Check if current path intersects with dynamic obstacles
		if not pathfinder.is_path_valid():
			pathfinder.recalculate_path()
			invalidated_count += 1
	
	if invalidated_count > 0:
		print("Invalidated ", invalidated_count, " paths due to dynamic obstacles")

func register_obstacle(obstacle: PathfinderObstacle):
	if obstacle not in obstacles:
		obstacles.append(obstacle)
		
		# Track dynamic obstacles separately
		if not obstacle.is_static:
			dynamic_obstacles.append(obstacle)
			print("Registered dynamic obstacle: ", obstacle.name)
		
		# Connect to change signal if dynamic
		if not obstacle.is_static and obstacle.has_signal("obstacle_changed"):
			if not obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
				obstacle.obstacle_changed.connect(_on_obstacle_changed)

func unregister_obstacle(obstacle: PathfinderObstacle):
	obstacles.erase(obstacle)
	dynamic_obstacles.erase(obstacle)
	
	if obstacle.has_signal("obstacle_changed") and obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
		obstacle.obstacle_changed.disconnect(_on_obstacle_changed)

func register_pathfinder(pathfinder: Pathfinder):
	if pathfinder not in pathfinders:
		pathfinders.append(pathfinder)

func unregister_pathfinder(pathfinder: Pathfinder):
	pathfinders.erase(pathfinder)

func find_path_for_circle(start: Vector2, end: Vector2, radius: float) -> PackedVector2Array:
	print("Finding circle path from ", start, " to ", end, " with radius ", radius)
	
	# Update grid if needed before pathfinding
	if grid_dirty:
		_update_grid_for_dynamic_obstacles()
		grid_dirty = false
		last_grid_update = 0.0
	
	# Direct path check
	if _is_safe_circle_path(start, end, radius):
		print("Safe direct path available")
		return PackedVector2Array([start, end])
	
	var start_grid = _find_safe_circle_position(start, radius)
	var end_grid = _find_safe_circle_position(end, radius)
	
	print("Grid start: ", start_grid, " Grid end: ", end_grid)
	
	if start_grid == Vector2.INF or end_grid == Vector2.INF:
		print("No valid start or end position found")
		return PackedVector2Array()
	
	var path = _a_star_pathfind_circle(start_grid, end_grid, radius)
	
	# Path smoothing
	if path.size() > 2:
		path = _smooth_circle_path(path, radius)
	
	print("Found path with ", path.size(), " points")
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

func _is_safe_circle_path(start: Vector2, end: Vector2, radius: float) -> bool:
	"""Check if a direct path is safe for a circle"""
	var distance = start.distance_to(end)
	var samples = max(int(distance / (grid_size * 0.2)), 12)
	
	for i in samples + 1:
		var t = float(i) / float(samples)
		var test_pos = start.lerp(end, t)
		
		if _is_circle_position_unsafe(test_pos, radius):
			return false
	
	return true

func _is_circle_position_unsafe(pos: Vector2, radius: float) -> bool:
	"""Check if a circle position collides with any obstacle"""
	var total_radius = radius + agent_buffer
	
	for obstacle in obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var world_poly = obstacle.get_world_polygon()
		var distance_to_obstacle = _distance_point_to_polygon(pos, world_poly)
		
		if distance_to_obstacle < total_radius:
			return true
	
	return false

func _distance_point_to_polygon(point: Vector2, polygon: PackedVector2Array) -> float:
	"""Calculate minimum distance from point to polygon"""
	if polygon.is_empty():
		return INF
	
	# Check if point is inside polygon first
	if _is_point_in_polygon(point, polygon):
		return 0.0
	
	var min_distance = INF
	
	# Check distance to each edge
	for i in polygon.size():
		var edge_start = polygon[i]
		var edge_end = polygon[(i + 1) % polygon.size()]
		var distance = _distance_point_to_line_segment(point, edge_start, edge_end)
		min_distance = min(min_distance, distance)
	
	return min_distance

func _distance_point_to_line_segment(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	"""Calculate distance from point to line segment"""
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	
	var line_len_sq = line_vec.length_squared()
	if line_len_sq < 0.001:
		return point.distance_to(line_start)
	
	var t = clamp(point_vec.dot(line_vec) / line_len_sq, 0.0, 1.0)
	var projection = line_start + t * line_vec
	
	return point.distance_to(projection)

func _find_safe_circle_position(pos: Vector2, radius: float) -> Vector2:
	"""Find a safe grid position for a circle"""
	var snapped = _snap_to_grid(pos)
	
	if grid.has(snapped) and not _is_circle_position_unsafe(snapped, radius):
		return snapped
	
	# Search for alternative position with expanding search radius
	var search_radiuses = [grid_size * 2, grid_size * 4, grid_size * 8, grid_size * 12]
	
	for search_radius in search_radiuses:
		var best_pos = Vector2.INF
		var best_score = -INF
		
		for grid_pos in grid.keys():
			var distance = pos.distance_to(grid_pos)
			if distance > search_radius:
				continue
				
			if _is_circle_position_unsafe(grid_pos, radius):
				continue
			
			# Calculate score (prefer closer positions with good clearance)
			var safety_score = _calculate_circle_safety_score(grid_pos, radius)
			var total_score = safety_score - (distance * 0.01)
			
			if total_score > best_score:
				best_pos = grid_pos
				best_score = total_score
		
		if best_pos != Vector2.INF:
			return best_pos
	
	print("Warning: Could not find safe position for radius ", radius, " near ", pos)
	return Vector2.INF

func _calculate_circle_safety_score(pos: Vector2, radius: float) -> float:
	"""Calculate safety score for a circle position"""
	var score = 100.0
	var total_radius = radius + agent_buffer
	
	for obstacle in obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var world_poly = obstacle.get_world_polygon()
		var distance = _distance_point_to_polygon(pos, world_poly)
		
		# Penalize positions close to obstacles
		if distance < total_radius * 2:
			var penalty = (total_radius * 2 - distance) * 0.5
			score -= penalty
	
	return score

func _snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		round(pos.x / grid_size) * grid_size,
		round(pos.y / grid_size) * grid_size
	)

func _a_star_pathfind_circle(start: Vector2, goal: Vector2, radius: float) -> PackedVector2Array:
	"""A* pathfinding for circle agents"""
	open_set.clear()
	closed_set.clear()
	came_from.clear()
	
	var start_node = PathNode.new(start, 0.0, _heuristic(start, goal))
	open_set.append(start_node)
	
	var iterations = 0
	var max_iterations = 3000
	
	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1
		
		# Find node with lowest f_score
		var current_idx = 0
		for i in range(1, open_set.size()):
			if open_set[i].f_score < open_set[current_idx].f_score:
				current_idx = i
		
		var current = open_set[current_idx]
		open_set.remove_at(current_idx)
		
		# Check if we reached the goal
		if current.position.distance_to(goal) < grid_size * 0.5:
			var path = _reconstruct_path(came_from, current.position, start)
			print("Circle path found after ", iterations, " iterations")
			return path
		
		closed_set[current.position] = true
		
		# Check neighbors
		var neighbors = _get_neighbors(current.position)
		for neighbor_pos in neighbors:
			if closed_set.has(neighbor_pos):
				continue
				
			# Check if neighbor is blocked in grid
			if grid.has(neighbor_pos) and not grid[neighbor_pos]:
				continue
				
			if _is_circle_position_unsafe(neighbor_pos, radius):
				continue
			
			if not _is_safe_circle_path(current.position, neighbor_pos, radius):
				continue
			
			var movement_cost = current.position.distance_to(neighbor_pos)
			var tentative_g = current.g_score + movement_cost
			
			# Check if this path is better
			var existing_node = null
			for node in open_set:
				if node.position == neighbor_pos:
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
	
	print("No circle path found after ", iterations, " iterations")
	return PackedVector2Array()

func _get_neighbors(pos: Vector2) -> Array[Vector2]:
	"""Get neighboring grid positions"""
	var neighbors: Array[Vector2] = []
	var directions = [
		Vector2(grid_size, 0), Vector2(-grid_size, 0),
		Vector2(0, grid_size), Vector2(0, -grid_size),
		Vector2(grid_size, grid_size), Vector2(-grid_size, -grid_size),
		Vector2(grid_size, -grid_size), Vector2(-grid_size, grid_size)
	]
	
	for direction in directions:
		var neighbor = pos + direction
		if grid.has(neighbor):
			neighbors.append(neighbor)
	
	return neighbors

func _heuristic(pos: Vector2, goal: Vector2) -> float:
	"""Heuristic function for A*"""
	return pos.distance_to(goal)

func _smooth_circle_path(path: PackedVector2Array, radius: float) -> PackedVector2Array:
	"""Smooth path by removing unnecessary waypoints"""
	if path.size() <= 2:
		return path
	
	var smoothed: PackedVector2Array = []
	smoothed.append(path[0])
	
	var current_index = 0
	
	while current_index < path.size() - 1:
		var farthest_safe = current_index + 1
		
		# Find the farthest point we can safely reach
		for i in range(current_index + 2, path.size()):
			if _is_safe_circle_path(path[current_index], path[i], radius):
				farthest_safe = i
			else:
				break
		
		current_index = farthest_safe
		smoothed.append(path[current_index])
	
	return smoothed

func _reconstruct_path(came_from_dict: Dictionary, current: Vector2, start: Vector2) -> PackedVector2Array:
	"""Reconstruct path from A* results"""
	var path: PackedVector2Array = []
	path.append(current)
	
	while came_from_dict.has(current) and current != start:
		current = came_from_dict[current]
		path.append(current)
	
	path.reverse()
	return path

func _find_obstacle_corners(polygon: PackedVector2Array) -> Array[Vector2]:
	"""Find sharp corners in obstacle polygon for avoidance"""
	var corners: Array[Vector2] = []
	
	if polygon.size() < 3:
		return corners
	
	for i in polygon.size():
		var prev_idx = (i - 1 + polygon.size()) % polygon.size()
		var next_idx = (i + 1) % polygon.size()
		
		var prev_point = polygon[prev_idx]
		var current_point = polygon[i]
		var next_point = polygon[next_idx]
		
		# Calculate angle at this vertex
		var vec1 = (prev_point - current_point).normalized()
		var vec2 = (next_point - current_point).normalized()
		
		var angle_rad = vec1.angle_to(vec2)
		var angle_deg = abs(rad_to_deg(angle_rad))
		
		# If angle is sharp enough, consider it a problematic corner
		if angle_deg < max_corner_angle:
			corners.append(current_point)
	
	return corners

# Debug functions
func get_dynamic_obstacle_count() -> int:
	return dynamic_obstacles.size()

func is_grid_dirty() -> bool:
	return grid_dirty

func force_grid_update():
	"""Force an immediate grid update"""
	if dynamic_obstacles.size() > 0:
		_update_grid_for_dynamic_obstacles()
		grid_dirty = false
		last_grid_update = 0.0
		print("Forced grid update completed")

# Legacy support
func find_path(start: Vector2, end: Vector2, agent_size: PackedVector2Array = PackedVector2Array()) -> PackedVector2Array:
	print("Warning: find_path() is deprecated. Use find_path_for_circle() instead.")
	
	var radius = 10.0
	if not agent_size.is_empty():
		var max_dist = 0.0
		for point in agent_size:
			max_dist = max(max_dist, point.length())
		radius = max_dist
	
	return find_path_for_circle(start, end, radius)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if bounds_polygon.size() < 3:
		warnings.append("Bounds polygon needs at least 3 points")
	
	if grid_size <= 0:
		warnings.append("Grid size must be greater than 0")
	
	if agent_buffer < 0:
		warnings.append("Agent buffer cannot be negative")
	
	if dynamic_update_rate <= 0:
		warnings.append("Dynamic update rate must be greater than 0")
	
	if dynamic_obstacles.size() > 10:
		warnings.append("Too many dynamic obstacles may impact performance")
	
	return warnings


func _on_obstacle_changed():
	"""Handle when a dynamic obstacle changes - Enhanced"""
	print("Dynamic obstacle changed - marking grid as dirty")
	grid_dirty = true
	# Force faster update for dynamic obstacles
	last_grid_update = dynamic_update_rate * 0.8

func _on_immediate_obstacle_change(obstacle: PathfinderObstacle):
	"""Handle immediate obstacle changes for fast-moving objects"""
	print("Immediate obstacle change detected for: ", obstacle.name)
	
	# Immediately check and invalidate affected paths
	var affected_pathfinders = _get_pathfinders_affected_by_obstacle(obstacle)
	for pathfinder in affected_pathfinders:
		if pathfinder.is_moving and pathfinder.current_path.size() > 0:
			print("Immediately invalidating path for pathfinder: ", pathfinder.name)
			pathfinder.path_invalidated.emit()
			if pathfinder.auto_recalculate:
				# Use call_deferred to avoid conflicts
				pathfinder.call_deferred("_attempt_path_recalculation")
	
	# Force immediate partial grid update around this obstacle
	_update_grid_around_obstacle(obstacle)

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
		for i in range(pathfinder.path_index, path.size()):
			if obstacle_bounds.has_point(path[i]):
				affected.append(pathfinder)
				break
			
			# Also check path segments
			if i < path.size() - 1:
				var segment_bounds = Rect2()
				segment_bounds = segment_bounds.expand(path[i])
				segment_bounds = segment_bounds.expand(path[i + 1])
				if segment_bounds.intersects(obstacle_bounds):
					affected.append(pathfinder)
					break
	
	return affected

func _update_grid_around_obstacle(obstacle: PathfinderObstacle):
	"""Update grid points around a specific obstacle"""
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
	
	print("Updated ", updated_count, " grid points around obstacle: ", obstacle.name)

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
