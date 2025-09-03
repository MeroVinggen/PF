@tool
extends RefCounted
class_name AStarPathfinding

var system: PathfinderSystem

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

func _init(pathfinder_system: PathfinderSystem):
	system = pathfinder_system

func find_path_for_circle(start: Vector2, end: Vector2, radius: float, buffer: float = 2.0) -> PackedVector2Array:
	print("=== PATHFINDING REQUEST ===")
	print("Start: ", start, " End: ", end, " Radius: ", radius, " Buffer: ", buffer)
	print("Grid dirty: ", system.grid_dirty)
	print("Total obstacles: ", system.obstacles.size())
	
	# Log all obstacle positions and states
	for i in range(system.obstacles.size()):
		var obs = system.obstacles[i]
		if is_instance_valid(obs):
			print("Obstacle ", i, ": pos=", obs.global_position, " static=", obs.is_static, " poly=", obs.get_world_polygon())
		else:
			print("Obstacle ", i, ": INVALID")
	
	if system.grid_dirty:
		print("Updating grid for dynamic obstacles...")
		system.grid_manager.update_grid_for_dynamic_obstacles()
		system.grid_dirty = false
		system.last_grid_update = 0.0
	
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

func _is_safe_circle_path(start: Vector2, end: Vector2, radius: float, buffer: float) -> bool:
	var distance = start.distance_to(end)
	var samples = max(int(distance / (system.grid_size * 0.5)), 8)
	
	for i in samples + 1:
		var t = float(i) / float(samples)
		var test_pos = start.lerp(end, t)
		
		if _is_circle_position_unsafe(test_pos, radius, buffer):
			return false
	
	return true

func _is_circle_position_unsafe(pos: Vector2, radius: float, buffer: float) -> bool:
	var total_radius = radius + buffer
	
	# Must be within bounds
	if not PathfindingUtils.is_point_in_polygon(pos, system.bounds_polygon):
		return true
	
	# Check distance to all obstacles
	for obstacle in system.obstacles:
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

func _find_safe_circle_position(pos: Vector2, radius: float, buffer: float) -> Vector2:
	# First try the exact position
	if not _is_circle_position_unsafe(pos, radius, buffer):
		return pos
	
	# Try snapped grid position
	var snapped = system.grid_manager.snap_to_grid(pos)
	if not _is_circle_position_unsafe(snapped, radius, buffer):
		return snapped
	
	# For larger agents or fine grids, search in expanding circles
	var search_step = min(system.grid_size * 0.5, radius * 0.5)  # Smaller steps for precision
	var max_search_radius = max(system.grid_size * 12, radius * 6)  # Scale with agent size
	
	# Try positions in expanding circles around target
	for search_radius in range(int(search_step), int(max_search_radius), int(search_step)):
		var angle_step = PI / 8  # 8 directions per circle
		
		for angle in range(0, int(TAU / angle_step)):
			var test_angle = angle * angle_step
			var offset = Vector2(cos(test_angle), sin(test_angle)) * search_radius
			var test_pos = pos + offset
			
			# Must be within bounds and not unsafe
			if PathfindingUtils.is_point_in_polygon(test_pos, system.bounds_polygon) and not _is_circle_position_unsafe(test_pos, radius, buffer):
				return test_pos
	
	# Final fallback: try grid points in expanded area
	for grid_pos in system.grid_manager.grid.keys():
		if pos.distance_to(grid_pos) <= max_search_radius:
			if not _is_circle_position_unsafe(grid_pos, radius, buffer):
				return grid_pos
	
	return Vector2.INF

func _a_star_pathfind_circle(start: Vector2, goal: Vector2, radius: float, buffer: float) -> PackedVector2Array:
	open_set.clear()
	closed_set.clear()
	came_from.clear()
	
	var start_node = PathNode.new(start, 0.0, _heuristic(start, goal))
	open_set.append(start_node)
	
	var iterations = 0
	var max_iterations = 3000  # Increased for better pathfinding
	
	# Dynamic goal tolerance based on agent size
	var goal_tolerance = max(system.grid_size * 0.7, radius * 0.5)
	
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
				if node.position.distance_to(neighbor_pos) < system.grid_size * 0.3:  # Close enough
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
	var step_size = system.grid_size
	if radius > system.grid_size * 0.7:
		step_size = max(system.grid_size * 0.5, radius * 0.8)  # Adaptive step size
	
	# Standard 8-direction movement
	var directions = [
		Vector2(step_size, 0), Vector2(-step_size, 0),
		Vector2(0, step_size), Vector2(0, -step_size),
		Vector2(step_size, step_size), Vector2(-step_size, -step_size),
		Vector2(step_size, -step_size), Vector2(-step_size, step_size)
	]
	
	# For larger agents, also try half-steps to find tighter passages
	if radius > system.grid_size * 0.5:
		var half_step = step_size * 0.5
		directions.append_array([
			Vector2(half_step, 0), Vector2(-half_step, 0),
			Vector2(0, half_step), Vector2(0, -half_step)
		])
	
	for direction in directions:
		var neighbor = pos + direction
		
		# Check if within bounds
		if PathfindingUtils.is_point_in_polygon(neighbor, system.bounds_polygon):
			neighbors.append(neighbor)
	
	return neighbors

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

func _heuristic(pos: Vector2, goal: Vector2) -> float:
	return pos.distance_to(goal)

func _reconstruct_path(came_from_dict: Dictionary, current: Vector2, start: Vector2) -> PackedVector2Array:
	var path: PackedVector2Array = []
	path.append(current)
	
	while came_from_dict.has(current) and current != start:
		current = came_from_dict[current]
		path.append(current)
	
	path.reverse()
	return path

func _distance_point_to_polygon(point: Vector2, polygon: PackedVector2Array) -> float:
	if polygon.is_empty():
		return INF
	
	if PathfindingUtils.is_point_in_polygon(point, polygon):
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
