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
@export var debug_draw: bool = false
@export var agent_buffer: float = 12.0  # Increased buffer for better corner clearance
@export var corner_buffer: float = 8.0  # Additional buffer specifically for corners
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
	var is_corner: bool = false  # Track if this node is near a corner
	
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
	_mark_corner_nodes()  # New: identify problematic corner areas
	print("PathfinderSystem initialized with ", grid.size(), " grid points")

func _find_and_register_obstacles():
	# Find obstacles in the scene
	var obstacle_nodes = get_tree().get_nodes_in_group("pathfinder_obstacles")
	for obstacle in obstacle_nodes:
		if obstacle is PathfinderObstacle:
			register_obstacle(obstacle)

func _find_and_register_pathfinders():
	# Find pathfinders in the scene
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

func _mark_corner_nodes():
	"""Mark grid nodes that are near obstacle corners for special handling"""
	var corner_nodes: Dictionary = {}
	
	for obstacle in obstacles:
		if not is_instance_valid(obstacle):
			continue
			
		var world_poly = obstacle.get_world_polygon()
		var corners = _find_obstacle_corners(world_poly)
		
		# Mark grid nodes near corners
		for corner in corners:
			var nearby_nodes = _get_nodes_in_radius(corner, corner_buffer + agent_buffer)
			for node_pos in nearby_nodes:
				if grid.has(node_pos):
					corner_nodes[node_pos] = true
	
	# Store corner information for pathfinding
	for pos in corner_nodes:
		if grid.has(pos):
			grid[pos] = {"valid": true, "is_corner": true}
		else:
			grid[pos] = {"valid": false, "is_corner": true}

func _find_obstacle_corners(polygon: PackedVector2Array) -> Array[Vector2]:
	"""Find sharp corners in obstacle polygon"""
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

func _get_nodes_in_radius(center: Vector2, radius: float) -> Array[Vector2]:
	"""Get all grid nodes within radius of a point"""
	var nodes: Array[Vector2] = []
	var search_steps = int(radius / grid_size) + 2
	
	for x in range(-search_steps, search_steps + 1):
		for y in range(-search_steps, search_steps + 1):
			var node_pos = center + Vector2(x * grid_size, y * grid_size)
			node_pos = _snap_to_grid(node_pos)
			
			if center.distance_to(node_pos) <= radius:
				nodes.append(node_pos)
	
	return nodes

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

func find_path(start: Vector2, end: Vector2, agent_size: PackedVector2Array = PackedVector2Array()) -> PackedVector2Array:
	print("Finding path from ", start, " to ", end)
	
	var centered_agent = _center_agent_polygon(agent_size)
	
	# Enhanced direct path check with corner avoidance
	if _is_safe_direct_path(start, end, centered_agent):
		print("Safe direct path available")
		return PackedVector2Array([start, end])
	
	var start_grid = _find_safe_grid_position(start, centered_agent)
	var end_grid = _find_safe_grid_position(end, centered_agent)
	
	print("Grid start: ", start_grid, " Grid end: ", end_grid)
	
	if start_grid == Vector2.INF or end_grid == Vector2.INF:
		print("No valid start or end position found")
		return PackedVector2Array()
	
	var path = _a_star_pathfind(start_grid, end_grid, centered_agent)
	
	# Enhanced path smoothing with corner awareness
	if path.size() > 2:
		path = _smooth_path_avoiding_corners(path, centered_agent)
	
	print("Found path with ", path.size(), " points")
	return path

func _is_safe_direct_path(start: Vector2, end: Vector2, agent_size: PackedVector2Array) -> bool:
	"""Enhanced direct path check that considers corner proximity"""
	var distance = start.distance_to(end)
	var samples = max(int(distance / (grid_size * 0.2)), 12)
	
	for i in samples + 1:
		var t = float(i) / float(samples)
		var test_pos = start.lerp(end, t)
		
		if _is_position_unsafe(test_pos, agent_size):
			return false
		
		# Additional check for corner proximity
		if _is_near_corner(test_pos, agent_size):
			return false
	
	return true

func _is_near_corner(pos: Vector2, agent_size: PackedVector2Array) -> bool:
	"""Check if position is too close to obstacle corners"""
	for obstacle in obstacles:
		if not is_instance_valid(obstacle):
			continue
			
		var world_poly = obstacle.get_world_polygon()
		var corners = _find_obstacle_corners(world_poly)
		
		for corner in corners:
			var agent_radius = _get_agent_radius(agent_size)
			if pos.distance_to(corner) < agent_radius + corner_buffer:
				return true
	
	return false

func _get_agent_radius(agent_size: PackedVector2Array) -> float:
	"""Get approximate radius of agent polygon"""
	if agent_size.is_empty():
		return 5.0
	
	var max_dist = 0.0
	for point in agent_size:
		max_dist = max(max_dist, point.length())
	
	return max_dist

func _find_safe_grid_position(pos: Vector2, agent_size: PackedVector2Array) -> Vector2:
	"""Find a safe grid position, avoiding corners"""
	var snapped = _snap_to_grid(pos)
	
	if grid.has(snapped) and not _is_position_unsafe(snapped, agent_size) and not _is_near_corner(snapped, agent_size):
		return snapped
	
	# Search for alternative position
	var search_radius = grid_size * 8
	var best_pos = Vector2.INF
	var best_distance = INF
	var best_score = -1.0
	
	for grid_pos in grid.keys():
		var distance = pos.distance_to(grid_pos)
		if distance > search_radius:
			continue
			
		if _is_position_unsafe(grid_pos, agent_size):
			continue
		
		# Calculate safety score (distance from corners and obstacles)
		var safety_score = _calculate_safety_score(grid_pos, agent_size)
		var total_score = safety_score - (distance * 0.01)  # Prefer closer positions slightly
		
		if total_score > best_score:
			best_pos = grid_pos
			best_distance = distance
			best_score = total_score
	
	return best_pos

func _calculate_safety_score(pos: Vector2, agent_size: PackedVector2Array) -> float:
	"""Calculate how safe a position is (higher = safer)"""
	var score = 100.0  # Base score
	var agent_radius = _get_agent_radius(agent_size)
	
	for obstacle in obstacles:
		if not is_instance_valid(obstacle):
			continue
			
		var world_poly = obstacle.get_world_polygon()
		var corners = _find_obstacle_corners(world_poly)
		
		# Penalize proximity to corners heavily
		for corner in corners:
			var dist_to_corner = pos.distance_to(corner)
			var min_safe_dist = agent_radius + corner_buffer
			
			if dist_to_corner < min_safe_dist * 2:
				var penalty = (min_safe_dist * 2 - dist_to_corner) * 2.0
				score -= penalty
		
		# Also consider general obstacle proximity
		var closest_point = _get_closest_point_on_polygon(pos, world_poly)
		var dist_to_obstacle = pos.distance_to(closest_point)
		var min_safe_obstacle_dist = agent_radius + agent_buffer
		
		if dist_to_obstacle < min_safe_obstacle_dist * 1.5:
			var penalty = (min_safe_obstacle_dist * 1.5 - dist_to_obstacle) * 0.5
			score -= penalty
	
	return score

func _get_closest_point_on_polygon(point: Vector2, polygon: PackedVector2Array) -> Vector2:
	"""Find the closest point on a polygon to the given point"""
	if polygon.is_empty():
		return point
	
	var closest_point = polygon[0]
	var closest_distance = point.distance_to(polygon[0])
	
	# Check each edge of the polygon
	for i in polygon.size():
		var edge_start = polygon[i]
		var edge_end = polygon[(i + 1) % polygon.size()]
		
		var closest_on_edge = _closest_point_on_line_segment(point, edge_start, edge_end)
		var distance = point.distance_to(closest_on_edge)
		
		if distance < closest_distance:
			closest_distance = distance
			closest_point = closest_on_edge
	
	return closest_point

func _closest_point_on_line_segment(point: Vector2, line_start: Vector2, line_end: Vector2) -> Vector2:
	"""Find the closest point on a line segment to the given point"""
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	
	var line_len_sq = line_vec.length_squared()
	if line_len_sq == 0:
		return line_start
	
	var t = point_vec.dot(line_vec) / line_len_sq
	t = clamp(t, 0.0, 1.0)
	
	return line_start + t * line_vec

func _center_agent_polygon(agent_polygon: PackedVector2Array) -> PackedVector2Array:
	if agent_polygon.is_empty():
		return agent_polygon
	
	var centroid = Vector2.ZERO
	for point in agent_polygon:
		centroid += point
	centroid /= agent_polygon.size()
	
	var centered: PackedVector2Array = []
	for point in agent_polygon:
		centered.append(point - centroid)
	
	return centered

func _smooth_path_avoiding_corners(path: PackedVector2Array, agent_size: PackedVector2Array) -> PackedVector2Array:
	"""Enhanced path smoothing that considers corner safety"""
	if path.size() <= 2:
		return path
	
	var smoothed: PackedVector2Array = []
	smoothed.append(path[0])
	
	var current_index = 0
	
	while current_index < path.size() - 1:
		var farthest_safe = current_index + 1
		
		# Find the farthest point we can safely reach
		for i in range(current_index + 2, path.size()):
			if _is_safe_direct_path(path[current_index], path[i], agent_size):
				farthest_safe = i
			else:
				break
		
		current_index = farthest_safe
		smoothed.append(path[current_index])
	
	return smoothed

func _snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		round(pos.x / grid_size) * grid_size,
		round(pos.y / grid_size) * grid_size
	)

func _a_star_pathfind(start: Vector2, goal: Vector2, agent_size: PackedVector2Array) -> PackedVector2Array:
	open_set.clear()
	closed_set.clear()
	came_from.clear()
	
	var start_node = PathNode.new(start, 0.0, _heuristic(start, goal))
	open_set.append(start_node)
	
	var iterations = 0
	var max_iterations = 3000
	
	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1
		
		var current_idx = 0
		for i in range(1, open_set.size()):
			if open_set[i].f_score < open_set[current_idx].f_score:
				current_idx = i
		
		var current = open_set[current_idx]
		open_set.remove_at(current_idx)
		
		if current.position.distance_to(goal) < grid_size * 0.5:
			var path = _reconstruct_path(came_from, current.position, start)
			print("Path found after ", iterations, " iterations")
			return path
		
		closed_set[current.position] = true
		
		var neighbors = _get_neighbors(current.position)
		for neighbor_pos in neighbors:
			if closed_set.has(neighbor_pos) or _is_position_unsafe(neighbor_pos, agent_size):
				continue
			
			if not _is_safe_direct_path(current.position, neighbor_pos, agent_size):
				continue
			
			var movement_cost = current.position.distance_to(neighbor_pos)
			
			# Add penalty for corner proximity
			if _is_near_corner(neighbor_pos, agent_size):
				movement_cost *= 2.0  # Make corner areas less attractive
			
			var tentative_g = current.g_score + movement_cost
			
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
	
	print("No path found after ", iterations, " iterations")
	return PackedVector2Array()

func _get_neighbors(pos: Vector2) -> Array[Vector2]:
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
	return pos.distance_to(goal)

func _is_position_unsafe(pos: Vector2, agent_size: PackedVector2Array) -> bool:
	"""Enhanced position safety check"""
	if agent_size.is_empty():
		for obstacle in obstacles:
			if not is_instance_valid(obstacle):
				continue
			if obstacle.is_point_inside(pos):
				return true
		return false
	
	# Check collision with expanded obstacles
	for obstacle in obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var obstacle_world_poly = obstacle.get_world_polygon()
		var expanded_obstacle = _expand_polygon(obstacle.obstacle_polygon, agent_buffer)
		var world_expanded: PackedVector2Array = []
		for p in expanded_obstacle:
			world_expanded.append(p + obstacle.global_position)
		
		if _polygons_intersect(agent_size, pos, world_expanded, Vector2.ZERO):
			return true
	
	return false

func _expand_polygon(poly: PackedVector2Array, buffer: float) -> PackedVector2Array:
	if poly.size() < 3 or buffer <= 0:
		return poly
	
	var expanded: PackedVector2Array = []
	
	for i in poly.size():
		var current = poly[i]
		var prev = poly[(i - 1 + poly.size()) % poly.size()]
		var next = poly[(i + 1) % poly.size()]
		
		var edge1 = (current - prev).normalized()
		var edge2 = (next - current).normalized()
		
		var normal1 = Vector2(-edge1.y, edge1.x)
		var normal2 = Vector2(-edge2.y, edge2.x)
		
		var bisector = (normal1 + normal2)
		if bisector.length_squared() < 0.001:
			bisector = normal1
		else:
			bisector = bisector.normalized()
		
		var angle_factor = 1.0 / max(0.1, abs(normal1.dot(bisector)))
		var offset = bisector * buffer * angle_factor
		
		expanded.append(current + offset)
	
	return expanded

func _polygons_intersect(poly1: PackedVector2Array, offset1: Vector2, poly2: PackedVector2Array, offset2: Vector2) -> bool:
	if poly1.is_empty() or poly2.is_empty():
		return false
	
	var world_poly1: PackedVector2Array = []
	for p in poly1:
		world_poly1.append(p + offset1)
	
	var world_poly2: PackedVector2Array = []
	for p in poly2:
		world_poly2.append(p + offset2)
	
	return _sat_intersect(world_poly1, world_poly2)

func _sat_intersect(poly1: PackedVector2Array, poly2: PackedVector2Array) -> bool:
	var axes: Array[Vector2] = []
	
	for i in poly1.size():
		var edge = poly1[(i + 1) % poly1.size()] - poly1[i]
		if edge.length_squared() > 0.001:
			var axis = Vector2(-edge.y, edge.x).normalized()
			axes.append(axis)
	
	for i in poly2.size():
		var edge = poly2[(i + 1) % poly2.size()] - poly2[i]
		if edge.length_squared() > 0.001:
			var axis = Vector2(-edge.y, edge.x).normalized()
			axes.append(axis)
	
	for axis in axes:
		var proj1 = _project_polygon(poly1, axis)
		var proj2 = _project_polygon(poly2, axis)
		
		if proj1.y < proj2.x or proj2.y < proj1.x:
			return false
	
	return true

func _project_polygon(poly: PackedVector2Array, axis: Vector2) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	
	var min_proj = poly[0].dot(axis)
	var max_proj = min_proj
	
	for i in range(1, poly.size()):
		var proj = poly[i].dot(axis)
		min_proj = min(min_proj, proj)
		max_proj = max(max_proj, proj)
	
	return Vector2(min_proj, max_proj)

func _reconstruct_path(came_from_dict: Dictionary, current: Vector2, start: Vector2) -> PackedVector2Array:
	var path: PackedVector2Array = []
	path.append(current)
	
	while came_from_dict.has(current) and current != start:
		current = came_from_dict[current]
		path.append(current)
	
	path.reverse()
	return path

func _draw():
	if not debug_draw:
		return
	
	# Draw bounds
	if bounds_polygon.size() >= 3:
		draw_colored_polygon(bounds_polygon, Color.BLUE * 0.2)
		draw_polyline(bounds_polygon + PackedVector2Array([bounds_polygon[0]]), Color.BLUE, 2.0)
	
	# Draw grid with corner highlighting
	var count = 0
	for pos in grid.keys():
		if count % 4 == 0:
			var color = Color.GRAY
			var size = 2.0
			
			if _is_position_unsafe(pos, PackedVector2Array()):
				color = Color.RED
			elif _is_near_corner(pos, PackedVector2Array()):
				color = Color.ORANGE
				size = 3.0
			
			draw_circle(pos, size, color)
		count += 1
	
	# Draw obstacle corners
	for obstacle in obstacles:
		if not is_instance_valid(obstacle):
			continue
		var world_poly = obstacle.get_world_polygon()
		var corners = _find_obstacle_corners(world_poly)
		for corner in corners:
			draw_circle(corner, corner_buffer, Color.YELLOW * 0.3)
			draw_arc(corner, corner_buffer, 0, TAU, 16, Color.YELLOW, 2.0)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if bounds_polygon.size() < 3:
		warnings.append("Bounds polygon needs at least 3 points")
	
	if grid_size <= 0:
		warnings.append("Grid size must be greater than 0")
	
	if corner_buffer < 0:
		warnings.append("Corner buffer cannot be negative")
	
	return warnings
