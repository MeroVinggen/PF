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
@export var agent_buffer: float = 5.0  # Additional buffer for safety
@export var corner_buffer: float = 8.0  # Extra buffer for corners
@export var max_corner_angle: float = 120.0  # Maximum angle for corner detection (degrees)

var grid: Dictionary = {}
var obstacles: Array[PathfinderObstacle] = []
var pathfinders: Array[Pathfinder] = []

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

func _initialize_system():
	_build_grid()
	_find_and_register_obstacles()
	_find_and_register_pathfinders()
	print("PathfinderSystem initialized with ", grid.size(), " grid points")

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
				grid[pos] = true

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

func register_obstacle(obstacle: PathfinderObstacle):
	if obstacle not in obstacles:
		obstacles.append(obstacle)

func unregister_obstacle(obstacle: PathfinderObstacle):
	obstacles.erase(obstacle)

func register_pathfinder(pathfinder: Pathfinder):
	if pathfinder not in pathfinders:
		pathfinders.append(pathfinder)

func unregister_pathfinder(pathfinder: Pathfinder):
	pathfinders.erase(pathfinder)

func find_path_for_circle(start: Vector2, end: Vector2, radius: float) -> PackedVector2Array:
	print("Finding circle path from ", start, " to ", end, " with radius ", radius)
	
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
	
	# Search for alternative position
	var search_radius = grid_size * 8
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
	
	return best_pos

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
			if closed_set.has(neighbor_pos) or _is_circle_position_unsafe(neighbor_pos, radius):
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

# Legacy support for polygon-based pathfinding (deprecated)
func find_path(start: Vector2, end: Vector2, agent_size: PackedVector2Array = PackedVector2Array()) -> PackedVector2Array:
	print("Warning: find_path() is deprecated. Use find_path_for_circle() instead.")
	
	# Convert polygon to approximate radius
	var radius = 10.0  # Default radius
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
	
	if corner_buffer < 0:
		warnings.append("Corner buffer cannot be negative")
	
	return warnings
