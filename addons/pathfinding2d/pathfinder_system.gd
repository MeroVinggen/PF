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
@export var dynamic_update_rate: float = 0.1
@export var auto_invalidate_paths: bool = true
@export var pathfinders: Array[Pathfinder] = []
@export var obstacles: Array[PathfinderObstacle] = []

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

# SIMPLIFIED: Combined dynamic update logic
func _update_dynamic_system(delta):
	last_grid_update += delta
	path_invalidation_timer += delta
	
	var should_update_grid = grid_dirty and last_grid_update >= dynamic_update_rate
	var should_invalidate_paths = auto_invalidate_paths and path_invalidation_timer >= dynamic_update_rate * 2
	
	if should_update_grid:
		_update_grid_for_dynamic_obstacles()
		grid_dirty = false
		last_grid_update = 0.0
	
	# Inline the _has_dynamic_obstacles() check
	if should_invalidate_paths and obstacles.any(func(o): return is_instance_valid(o) and not o.is_static):
		_invalidate_affected_paths()
		path_invalidation_timer = 0.0


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
	if dynamic_obstacles.is_empty():
		return
	
	var affected_bounds = _get_dynamic_obstacles_bounds()
	if affected_bounds.size.x <= 0 or affected_bounds.size.y <= 0:
		return
	
	for grid_pos in grid.keys():
		if affected_bounds.has_point(grid_pos):
			grid[grid_pos] = _is_grid_point_clear(grid_pos)

# SIMPLIFIED: Get bounds of dynamic obstacles
func _get_dynamic_obstacles_bounds() -> Rect2:
	# Filter dynamic obstacles inline instead of using separate array
	var dynamic_obs = obstacles.filter(func(o): return is_instance_valid(o) and not o.is_static)
	if dynamic_obs.is_empty():
		return Rect2()
	
	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)
	
	for obstacle in dynamic_obs:
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
	if not obstacle.is_static:
		if not obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
			obstacle.obstacle_changed.connect(_on_obstacle_changed)
	if not obstacle.static_state_changed.is_connected(_on_obstacle_static_changed):
		obstacle.static_state_changed.connect(_on_obstacle_static_changed.bind(obstacle))

func _on_obstacle_static_changed(is_now_static: bool, obstacle: PathfinderObstacle):
	if is_now_static:
		# Became static - remove from dynamic list
		dynamic_obstacles.erase(obstacle)
		if obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
			obstacle.obstacle_changed.disconnect(_on_obstacle_changed)
	else:
		# Became dynamic - add to dynamic list
		if obstacle not in dynamic_obstacles:
			dynamic_obstacles.append(obstacle)
		if not obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
			obstacle.obstacle_changed.connect(_on_obstacle_changed)
	
	# Trigger grid update since obstacle type changed
	grid_dirty = true

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

func find_path_for_circle(start: Vector2, end: Vector2, radius: float) -> PackedVector2Array:
	if grid_dirty:
		_update_grid_for_dynamic_obstacles()
		grid_dirty = false
		last_grid_update = 0.0
	
	# Try direct path first
	if _is_safe_circle_path(start, end, radius):
		return PackedVector2Array([start, end])
	
	var start_grid = _find_safe_circle_position(start, radius)
	var end_grid = _find_safe_circle_position(end, radius)
	
	if start_grid == Vector2.INF or end_grid == Vector2.INF:
		return PackedVector2Array()
	
	var path = _a_star_pathfind_circle(start_grid, end_grid, radius)
	
	if path.size() > 2:
		path = _smooth_circle_path(path, radius)
	
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
	var distance = start.distance_to(end)
	var samples = max(int(distance / (grid_size * 0.5)), 8)
	
	for i in samples + 1:
		var t = float(i) / float(samples)
		var test_pos = start.lerp(end, t)
		
		if _is_circle_position_unsafe(test_pos, radius):
			return false
	
	return true

func _is_circle_position_unsafe(pos: Vector2, radius: float) -> bool:
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

func _find_safe_circle_position(pos: Vector2, radius: float) -> Vector2:
	var snapped = _snap_to_grid(pos)
	
	if grid.has(snapped) and not _is_circle_position_unsafe(snapped, radius):
		return snapped
	
	# Simplified search - just check nearby grid points
	for search_radius in [grid_size * 2, grid_size * 4, grid_size * 8]:
		for grid_pos in grid.keys():
			if pos.distance_to(grid_pos) > search_radius:
				continue
			
			if not _is_circle_position_unsafe(grid_pos, radius):
				return grid_pos
	
	return Vector2.INF

func _snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		round(pos.x / grid_size) * grid_size,
		round(pos.y / grid_size) * grid_size
	)

func _a_star_pathfind_circle(start: Vector2, goal: Vector2, radius: float) -> PackedVector2Array:
	open_set.clear()
	closed_set.clear()
	came_from.clear()
	
	var start_node = PathNode.new(start, 0.0, _heuristic(start, goal))
	open_set.append(start_node)
	
	var iterations = 0
	var max_iterations = 2000
	
	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1
		
		# Find lowest f_score
		var current_idx = 0
		for i in range(1, open_set.size()):
			if open_set[i].f_score < open_set[current_idx].f_score:
				current_idx = i
		
		var current = open_set[current_idx]
		open_set.remove_at(current_idx)
		
		if current.position.distance_to(goal) < grid_size * 0.5:
			return _reconstruct_path(came_from, current.position, start)
		
		closed_set[current.position] = true
		
		for neighbor_pos in _get_neighbors(current.position):
			if closed_set.has(neighbor_pos):
				continue
			
			if grid.has(neighbor_pos) and not grid[neighbor_pos]:
				continue
			
			if _is_circle_position_unsafe(neighbor_pos, radius):
				continue
			
			if not _is_safe_circle_path(current.position, neighbor_pos, radius):
				continue
			
			var movement_cost = current.position.distance_to(neighbor_pos)
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

func _smooth_circle_path(path: PackedVector2Array, radius: float) -> PackedVector2Array:
	if path.size() <= 2:
		return path
	
	var smoothed: PackedVector2Array = []
	smoothed.append(path[0])
	
	var current_index = 0
	
	while current_index < path.size() - 1:
		var farthest_safe = current_index + 1
		
		for i in range(current_index + 2, path.size()):
			if _is_safe_circle_path(path[current_index], path[i], radius):
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
	return obstacles.filter(func(o): return is_instance_valid(o) and not o.is_static).size()


func is_grid_dirty() -> bool:
	return grid_dirty

func force_grid_update():
	if dynamic_obstacles.size() > 0:
		_update_grid_for_dynamic_obstacles()
		grid_dirty = false
		last_grid_update = 0.0

# SIMPLIFIED: Single obstacle change handler
func _on_obstacle_changed():
	grid_dirty = true
	for pathfinder in pathfinders:
		if is_instance_valid(pathfinder) and pathfinder.is_moving:
			pathfinder.consecutive_failed_recalcs = 0
			pathfinder.call_deferred("_recalculate_or_find_alternative")

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if bounds_polygon.size() < 3:
		warnings.append("Bounds polygon needs at least 3 points")
	
	if grid_size <= 0:
		warnings.append("Grid size must be greater than 0")
	
	if agent_buffer < 0:
		warnings.append("Agent buffer cannot be negative")
	
	return warnings
