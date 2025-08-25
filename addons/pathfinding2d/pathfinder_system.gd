@tool
extends Node2D
class_name PathfinderSystem

@export var bounds_polygon: PackedVector2Array = PackedVector2Array([
	Vector2(-500, -500),
	Vector2(500, -500),
	Vector2(500, 500),
	Vector2(-500, 500)
])

@export var grid_size: float = 25.0  # Reduced grid size for better pathfinding
@export var debug_draw: bool = false
@export var agent_buffer: float = 5.0  # Buffer distance to avoid touching obstacles

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
	_register_obstacles()
	_register_pathfinders()
	print("PathfinderSystem initialized with ", grid.size(), " grid points")

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
		return true  # If no valid bounds, allow all points
	
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

func _register_obstacles():
	obstacles.clear()
	var nodes = get_tree().get_nodes_in_group("pathfinder_obstacles")
	for node in nodes:
		if node is PathfinderObstacle:
			obstacles.append(node)
	print("Registered ", obstacles.size(), " obstacles")

func _register_pathfinders():
	pathfinders.clear()
	var nodes = get_tree().get_nodes_in_group("pathfinders")
	for node in nodes:
		if node is Pathfinder:
			pathfinders.append(node)
	print("Registered ", pathfinders.size(), " pathfinders")

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
	print("Agent size: ", agent_size.size(), " points")
	
	var start_grid = _snap_to_grid(start)
	var end_grid = _snap_to_grid(end)
	
	print("Grid start: ", start_grid, " Grid end: ", end_grid)
	
	if not grid.has(start_grid):
		print("Start position not in grid")
		# Try to find nearest valid grid point
		start_grid = _find_nearest_valid_position(start_grid, agent_size)
		if start_grid == Vector2.INF:
			return PackedVector2Array()
	
	if not grid.has(end_grid):
		print("End position not in grid")
		# Try to find nearest valid grid point
		end_grid = _find_nearest_valid_position(end_grid, agent_size)
		if end_grid == Vector2.INF:
			return PackedVector2Array()
	
	if _is_position_blocked(start_grid, agent_size):
		print("Start position is blocked")
		return PackedVector2Array()
	
	if _is_position_blocked(end_grid, agent_size):
		print("End position is blocked")
		return PackedVector2Array()
	
	var path = _a_star_pathfind(start_grid, end_grid, agent_size)
	print("Found path with ", path.size(), " points")
	return path

func _find_nearest_valid_position(pos: Vector2, agent_size: PackedVector2Array) -> Vector2:
	var search_radius = grid_size * 3
	var best_pos = Vector2.INF
	var best_distance = INF
	
	for grid_pos in grid.keys():
		var distance = pos.distance_to(grid_pos)
		if distance <= search_radius and distance < best_distance:
			if not _is_position_blocked(grid_pos, agent_size):
				best_pos = grid_pos
				best_distance = distance
	
	return best_pos

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
	var max_iterations = 1000
	
	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1
		
		# Find node with lowest f_score
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
		
		# Check neighbors
		var neighbors = _get_neighbors(current.position)
		for neighbor_pos in neighbors:
			if closed_set.has(neighbor_pos) or _is_position_blocked(neighbor_pos, agent_size):
				continue
			
			var tentative_g = current.g_score + current.position.distance_to(neighbor_pos)
			
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

func _is_position_blocked(pos: Vector2, agent_size: PackedVector2Array) -> bool:
	# If no agent size specified, just check point collision
	if agent_size.is_empty():
		for obstacle in obstacles:
			if obstacle.is_point_inside(pos):
				return true
		return false
	
	# Check if agent polygon at this position would intersect with any obstacle
	for obstacle in obstacles:
		if _polygons_intersect(agent_size, pos, obstacle.obstacle_polygon, obstacle.global_position):
			return true
	return false

func _polygons_intersect(poly1: PackedVector2Array, offset1: Vector2, poly2: PackedVector2Array, offset2: Vector2) -> bool:
	if poly1.is_empty() or poly2.is_empty():
		return false
	
	# Transform polygons to world space with buffer
	var world_poly1: PackedVector2Array = []
	for p in poly1:
		world_poly1.append(p + offset1)
	
	var world_poly2: PackedVector2Array = []
	# Add buffer to obstacle polygon
	var buffered_poly2 = _expand_polygon(poly2, agent_buffer)
	for p in buffered_poly2:
		world_poly2.append(p + offset2)
	
	# Separating Axis Theorem
	return _sat_intersect(world_poly1, world_poly2)

func _expand_polygon(poly: PackedVector2Array, buffer: float) -> PackedVector2Array:
	if poly.size() < 3 or buffer <= 0:
		return poly
	
	var expanded: PackedVector2Array = []
	
	for i in poly.size():
		var current = poly[i]
		var prev = poly[(i - 1 + poly.size()) % poly.size()]
		var next = poly[(i + 1) % poly.size()]
		
		# Calculate edge normals
		var edge1 = (current - prev).normalized()
		var edge2 = (next - current).normalized()
		var normal1 = Vector2(-edge1.y, edge1.x)
		var normal2 = Vector2(-edge2.y, edge2.x)
		
		# Average the normals for the vertex offset direction
		var offset_dir = (normal1 + normal2).normalized()
		expanded.append(current + offset_dir * buffer)
	
	return expanded

func _sat_intersect(poly1: PackedVector2Array, poly2: PackedVector2Array) -> bool:
	var polygons = [poly1, poly2]
	
	for poly in polygons:
		for i in poly.size():
			var edge = poly[(i + 1) % poly.size()] - poly[i]
			var axis = Vector2(-edge.y, edge.x).normalized()
			
			if axis.length_squared() < 0.001:  # Skip zero-length axes
				continue
			
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
	
	# Draw grid (only a subset to avoid performance issues)
	var count = 0
	for pos in grid.keys():
		if count % 4 == 0:  # Only draw every 4th grid point
			draw_circle(pos, 2.0, Color.GRAY)
		count += 1

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if bounds_polygon.size() < 3:
		warnings.append("Bounds polygon needs at least 3 points")
	
	if grid_size <= 0:
		warnings.append("Grid size must be greater than 0")
	
	return warnings
