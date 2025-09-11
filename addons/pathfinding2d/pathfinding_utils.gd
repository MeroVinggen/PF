@tool
extends RefCounted
class_name PathfindingUtils

# Point-in-polygon test using ray casting algorithm
static func is_point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
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

# Find closest point on line segment to given point
static func closest_point_on_line_segment(point: Vector2, line_start: Vector2, line_end: Vector2) -> Vector2:
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	
	var line_len_sq = line_vec.length_squared()
	if line_len_sq < PathfindingConstants.MIN_LINE_LENGTH_SQUARED:
		return line_start
	
	var t = clamp(point_vec.dot(line_vec) / line_len_sq, 0.0, 1.0)
	return line_start + t * line_vec

# Get bounding rectangle of a polygon
static func get_polygon_bounds(polygon: PackedVector2Array) -> Rect2:
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

# Calculate center point of polygon
static func get_polygon_center(polygon: PackedVector2Array) -> Vector2:
	if polygon.is_empty():
		return Vector2.ZERO
	
	var sum = Vector2.ZERO
	for point in polygon:
		sum += point
	
	return sum / polygon.size()

static func is_safe_circle_path(system: PathfinderSystem, start: Vector2, end: Vector2, agent_full_size: float, mask: int) -> bool:
	var distance = start.distance_to(end)
	var samples = max(int(distance / (system.grid_size * PathfindingConstants.SAMPLE_DISTANCE_FACTOR)), PathfindingConstants.MIN_PATH_SAMPLES)
	
	# Get obstacles in path region once
	var path_bounds_min = Vector2(min(start.x, end.x), min(start.y, end.y)) - Vector2(agent_full_size, agent_full_size)
	var path_bounds_max = Vector2(max(start.x, end.x), max(start.y, end.y)) + Vector2(agent_full_size, agent_full_size)
	var path_obstacles = system.spatial_partition.get_obstacles_in_region(path_bounds_min, path_bounds_max)
	
	for i in samples + 1:
		var t = float(i) / float(samples)
		var test_pos = start.lerp(end, t)
		
		if is_position_unsafe_with_obstacles(system, test_pos, agent_full_size, path_obstacles, mask):
			system.array_pool.return_obstacles_array(path_obstacles)
			return false
	
	system.array_pool.return_obstacles_array(path_obstacles)
	return true

static func is_position_unsafe_with_obstacles(system: PathfinderSystem, pos: Vector2, agent_full_size: float, obstacles: Array[PathfinderObstacle], mask: int) -> bool:
	if not PathfindingUtils.is_point_in_polygon(pos, system.bounds_polygon):
		return true
	
	for obstacle in obstacles:
		if obstacle.disabled:
			continue
		if not ((obstacle.layer & mask) != 0):
			continue
		var world_poly = obstacle.get_world_polygon()
		if world_poly.is_empty():
			system.array_pool.return_packedVector2_array(world_poly)
			continue
			
		var distance_to_obstacle = distance_point_to_polygon(pos, world_poly, agent_full_size)
		system.array_pool.return_packedVector2_array(world_poly)
		if distance_to_obstacle < (agent_full_size - PathfindingConstants.SAFETY_MARGIN):
			return true
	
	return false

static func distance_point_to_polygon(point: Vector2, polygon: PackedVector2Array, radius: float) -> float:
	if polygon.is_empty():
		return INF
	
	var bounds = PathfindingUtils.get_polygon_bounds(polygon)
	bounds = bounds.grow(-radius)  # Shrink by agent size
	if bounds.has_point(point):
		return 0.0  # Definitely inside, skip expensive checks
	
	if PathfindingUtils.is_point_in_polygon(point, polygon):
		return 0.0
	
	var min_distance = INF
	
	for i in polygon.size():
		var edge_start = polygon[i]
		var edge_end = polygon[(i + 1) % polygon.size()]
		var distance = distance_point_to_line_segment(point, edge_start, edge_end)
		min_distance = min(min_distance, distance)
	
	return min_distance

static func distance_point_to_line_segment(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	
	var line_len_sq = line_vec.length_squared()
	if line_len_sq < PathfindingConstants.MIN_LINE_LENGTH_SQUARED:
		return point.distance_to(line_start)
	
	var t = clamp(point_vec.dot(line_vec) / line_len_sq, 0.0, 1.0)
	var projection = line_start + t * line_vec
	
	return point.distance_to(projection)

static func is_circle_position_unsafe(system: PathfinderSystem, pos: Vector2, agent_full_size: float, mask: int) -> bool:
	#print_stack()
	
	# Use spatial partition instead of system's method
	if not is_point_in_polygon(pos, system.bounds_polygon):
		return true
	
	var nearby_obstacles = system.spatial_partition.get_obstacles_near_point(pos, agent_full_size)
	for obstacle: PathfinderObstacle in nearby_obstacles:
		if obstacle.disabled:
			continue
		if not ((obstacle.layer & mask) != 0):
			continue
		var world_poly = obstacle.get_world_polygon()
		if world_poly.is_empty():
			system.array_pool.return_packedVector2_array(world_poly)
			continue
			
		var distance_to_obstacle = PathfindingUtils.distance_point_to_polygon(pos, world_poly, agent_full_size)
		system.array_pool.return_packedVector2_array(world_poly)
		if distance_to_obstacle < (agent_full_size - PathfindingConstants.SAFETY_MARGIN):
			return true
	
	return false

static func is_path_safe(system: PathfinderSystem, path: PackedVector2Array, current_pos: Vector2, path_index: int, agent_full_size: float, mask: int) -> bool:
	if not system or path.is_empty() or path_index >= path.size():
		return false
	
	# Check current position
	if PathfindingUtils.is_circle_position_unsafe(system, current_pos, agent_full_size, mask):
		return false
	
	# Check next waypoint
	if path_index < path.size():
		var next_waypoint = path[path_index]
		if PathfindingUtils.is_circle_position_unsafe(system, next_waypoint, agent_full_size, mask):
			return false
		if not PathfindingUtils.is_safe_circle_path(system, current_pos, next_waypoint, agent_full_size, mask):
			return false
	
	return true
