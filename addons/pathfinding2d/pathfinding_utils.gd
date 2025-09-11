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
	if not is_point_in_polygon(pos, system.bounds_polygon):
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
	
	var bounds = get_polygon_bounds(polygon)
	bounds = bounds.grow(-radius)  # Shrink by agent size
	if bounds.has_point(point):
		return 0.0  # Definitely inside, skip expensive checks
	
	if is_point_in_polygon(point, polygon):
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
			
		var distance_to_obstacle = distance_point_to_polygon(pos, world_poly, agent_full_size)
		system.array_pool.return_packedVector2_array(world_poly)
		if distance_to_obstacle < (agent_full_size - PathfindingConstants.SAFETY_MARGIN):
			return true
	
	return false

static func is_path_safe(system: PathfinderSystem, path: PackedVector2Array, current_pos: Vector2, path_index: int, agent_full_size: float, mask: int) -> bool:
	if not system or path.is_empty() or path_index >= path.size():
		return false
	
	# Check current position
	if is_circle_position_unsafe(system, current_pos, agent_full_size, mask):
		return false
	
	# Check next waypoint
	if path_index < path.size():
		var next_waypoint = path[path_index]
		if is_circle_position_unsafe(system, next_waypoint, agent_full_size, mask):
			return false
		if not is_safe_circle_path(system, current_pos, next_waypoint, agent_full_size, mask):
			return false
	
	return true

static func find_closest_safe_point(system: PathfinderSystem, unsafe_pos: Vector2, agent_full_size: float, mask: int) -> Vector2:
	# First, find which obstacle(s) contain this point
	var containing_obstacles: Array[PathfinderObstacle] = system.array_pool.get_obstacle_array()
	var nearby_obstacles = system.spatial_partition.get_obstacles_near_point(unsafe_pos, agent_full_size + PathfindingConstants.CLEARANCE_BASE_ADDITION)
	for obstacle in nearby_obstacles:
		if is_instance_valid(obstacle) and obstacle.is_point_inside(unsafe_pos):
			containing_obstacles.append(obstacle)
	
	# Point is not actually inside an obstacle, check if it's just too close
	if containing_obstacles.is_empty():
		print("Point not inside obstacle, finding safe position nearby...")
		system.array_pool.return_obstacles_array(containing_obstacles)
		return find_safe_circle_position(system, unsafe_pos, agent_full_size, mask)
	
	print("Point is inside ", containing_obstacles.size(), " obstacle(s)")
	
	# For each containing obstacle, find multiple candidate points
	var candidates: Array[Vector2] = system.array_pool.get_vector2_array()
	
	for obstacle in containing_obstacles:
		var safe_pos = find_closest_point_outside_obstacle(system, unsafe_pos, obstacle, agent_full_size, mask)
		if safe_pos != Vector2.INF:
			candidates.append(safe_pos)
		
		# Also try finding safe points in cardinal directions from obstacle edges
		var world_poly = obstacle.get_world_polygon()
		var poly_center = get_polygon_center(world_poly)
		system.array_pool.return_packedVector2_array(world_poly)
		var directions = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
		
		for direction in directions:
			var test_distance: float = (agent_full_size + PathfindingConstants.FALLBACK_SEARCH_BUFFER)  # Generous distance
			var candidate: Vector2 = unsafe_pos + direction * test_distance
			
			if is_point_in_polygon(candidate, system.bounds_polygon) and \
			   not is_circle_position_unsafe(system, candidate, agent_full_size, mask):
				candidates.append(candidate)
	
	system.array_pool.return_obstacles_array(containing_obstacles)
	
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
		system.array_pool.return_vector2_array(candidates)
		return best_candidate
	
	# Fallback: search in expanding circles with larger steps
	print("Using enhanced fallback search method...")
	var search_step: int = int(max(system.grid_size, agent_full_size + PathfindingConstants.ENHANCED_SEARCH_STEP_BUFFER))  # Larger search steps
	var max_search_radius: int = int(max(system.grid_size * PathfindingConstants.CLEARANCE_BASE_ADDITION, agent_full_size * PathfindingConstants.CLEARANCE_SAFETY_MARGIN))  # Expanded search area
	
	# Try positions in expanding circles around target
	for search_radius in range(search_step, max_search_radius, search_step):
		for angle in range(0, int(TAU / PathfindingConstants.ENHANCED_SEARCH_ANGLE_STEP)):
			var test_angle = angle * PathfindingConstants.ENHANCED_SEARCH_ANGLE_STEP
			var offset = Vector2(cos(test_angle), sin(test_angle)) * search_radius
			var test_pos = unsafe_pos + offset
			
			# Must be within bounds and not unsafe
			if is_point_in_polygon(test_pos, system.bounds_polygon) and \
			   not is_circle_position_unsafe(system, test_pos, agent_full_size, mask):
				print("Fallback found safe point at: ", test_pos)
				system.array_pool.return_vector2_array(candidates)
				return test_pos
	
	print("Could not find any safe point!")
	system.array_pool.return_vector2_array(candidates)
	return Vector2.INF

static func find_closest_point_outside_obstacle(system: PathfinderSystem, point: Vector2, obstacle: PathfinderObstacle, agent_full_size: float, mask: int) -> Vector2:
	"""Find closest point outside a specific obstacle with better clearance"""
	var world_poly = obstacle.get_world_polygon()
	if world_poly.is_empty():
		system.array_pool.return_packedVector2_array(world_poly)
		return Vector2.INF
	
	var closest_point = Vector2.INF
	var closest_distance = INF
	
	# Increase clearance distance significantly for better pathfinding success
	var base_clearance: float = agent_full_size + PathfindingConstants.CLEARANCE_BASE_ADDITION  # Increased base clearance
	
	# Check each edge of the polygon
	for i in world_poly.size():
		var edge_start = world_poly[i]
		var edge_end = world_poly[(i + 1) % world_poly.size()]
		
		# Find closest point on this edge
		var edge_point = closest_point_on_line_segment(point, edge_start, edge_end)
		
		# Calculate outward direction from obstacle
		var direction = (point - edge_point).normalized()
		if direction.length() < PathfindingConstants.MIN_DIRECTION_LENGTH:  # Handle case where point is exactly on edge
			# Use edge normal instead
			var edge_vector = (edge_end - edge_start).normalized()
			direction = Vector2(-edge_vector.y, edge_vector.x)  # Perpendicular (outward)
			
			# Determine which side is "outward" by testing
			var test_point1 = edge_point + direction * PathfindingConstants.DIRECTION_TEST_DISTANCE
			var test_point2 = edge_point - direction * PathfindingConstants.DIRECTION_TEST_DISTANCE
			
			if is_point_in_polygon(test_point1, world_poly):
				direction = -direction  # Flip if we picked the wrong direction
		
		# Try multiple clearance distances for robustness
		var clearance_distances = []
		for multiplier in PathfindingConstants.CLEARANCE_MULTIPLIERS:
			clearance_distances.append(base_clearance + PathfindingConstants.CLEARANCE_SAFETY_MARGIN * multiplier)
		
		for clearance_distance in clearance_distances:
			var safe_candidate = edge_point + direction * clearance_distance
			
			# Verify this candidate is good
			if is_point_in_polygon(safe_candidate, system.bounds_polygon) and \
			   not is_circle_position_unsafe(system, safe_candidate, agent_full_size, mask):
				var distance = point.distance_to(safe_candidate)
				if distance < closest_distance:
					closest_distance = distance
					closest_point = safe_candidate
					break  # Found a good point, stop trying further distances
	
	# If no edge-based solution worked, try radial approach with multiple distances
	if closest_point == Vector2.INF:
		print("Edge-based approach failed, trying radial approach...")
		var poly_center = get_polygon_center(world_poly)
		system.array_pool.return_packedVector2_array(world_poly)
		var direction = (point - poly_center).normalized()
		
		# Try progressively larger distances
		var test_distances = []
		for multiplier in PathfindingConstants.CLEARANCE_MULTIPLIERS:
			test_distances.append(base_clearance + PathfindingConstants.CLEARANCE_SAFETY_MARGIN * multiplier)
		
		for dist in test_distances:
			var candidate = point + direction * dist
			if is_point_in_polygon(candidate, system.bounds_polygon) and \
			   not is_circle_position_unsafe(system, candidate, agent_full_size, mask):
				print("Radial approach found safe point at distance: ", dist)
				return candidate
		
		# Last resort: try 8 cardinal directions from the point
		print("Trying cardinal directions as last resort...")
		var directions = PathfindingConstants.CARDINAL_DIRECTIONS + PathfindingConstants.DIAGONAL_DIRECTIONS
		
		for dir in directions:
			for dist in test_distances:
				var candidate = point + dir * dist
				if is_point_in_polygon(candidate, system.bounds_polygon) and \
				   not is_circle_position_unsafe(system, candidate, agent_full_size, mask):
					print("Cardinal direction found safe point: ", candidate)
					return candidate
	
	system.array_pool.return_packedVector2_array(world_poly)
	return closest_point

static func find_safe_circle_position(system: PathfinderSystem, pos: Vector2, agent_full_size: float, mask: int) -> Vector2:
	print("DEBUG: Finding safe position for: ", pos)
	
	# First try the exact position
	if not is_circle_position_unsafe(system, pos, agent_full_size, mask):
		print("DEBUG: Exact position is safe")
		return pos
	
	print("DEBUG: Exact position is unsafe, trying snapped")
	# Try snapped grid position
	var snapped = system.grid_manager.snap_to_grid(pos)
	if not PathfindingUtils.is_circle_position_unsafe(system, snapped, agent_full_size, mask):
		print("DEBUG: Snapped position is safe: ", snapped)
		return snapped
	
	print("DEBUG: Snapped position also unsafe, starting search...")
	var search_step = min(system.grid_size * PathfindingConstants.SEARCH_STEP_FACTOR, agent_full_size * PathfindingConstants.SEARCH_STEP_FACTOR)
	var max_search_radius = max(system.grid_size * PathfindingConstants.MAX_SEARCH_RADIUS_GRID_FACTOR, agent_full_size * PathfindingConstants.MAX_SEARCH_RADIUS_AGENT_FACTOR)
	
	print("DEBUG: Search params - step:", search_step, " max_radius:", max_search_radius)
	
	# Try positions in expanding circles around target
	for search_radius in range(int(search_step), int(max_search_radius), int(search_step)):
		print("DEBUG: Trying search radius: ", search_radius)
		
		var angle_step = PathfindingConstants.SEARCH_ANGLE_STEP
		
		for angle in range(0, int(TAU / angle_step)):
			var test_angle = angle * angle_step
			var offset = Vector2(cos(test_angle), sin(test_angle)) * search_radius
			var test_pos = pos + offset
			
			# Must be within bounds and not unsafe
			if PathfindingUtils.is_point_in_polygon(test_pos, system.bounds_polygon) and not PathfindingUtils.is_circle_position_unsafe(system, test_pos, agent_full_size, mask):
				return test_pos
	
	# Final fallback: try grid points in expanded area
	for grid_pos in system.grid_manager.grid.keys():
		if pos.distance_to(grid_pos) <= max_search_radius:
			if not PathfindingUtils.is_circle_position_unsafe(system, grid_pos, agent_full_size, mask):
				return grid_pos
	
	return Vector2.INF

static func smooth_circle_path(system: PathfinderSystem, path: PackedVector2Array, agent_full_size: float, mask: int) -> PackedVector2Array:
	if path.size() <= 2:
		return path
	
	# will be returned to pool in pathfinding_agent
	var smoothed: PackedVector2Array = system.array_pool.get_packedVector2_array()
	smoothed.append(path[0])
	
	var current_index = 0
	
	while current_index < path.size() - 1:
		var farthest_safe = current_index + 1
		
		for i in range(current_index + 2, path.size()):
			if PathfindingUtils.is_safe_circle_path(system, path[current_index], path[i], agent_full_size, mask):
				farthest_safe = i
			else:
				break
		
		current_index = farthest_safe
		smoothed.append(path[current_index])
	
	return smoothed

static func find_path_for_circle(system: PathfinderSystem, start: Vector2, end: Vector2, agent_full_size: float = PathfindingConstants.SAFETY_MARGIN, mask: int = 1) -> PackedVector2Array:
	print("=== PATHFINDING REQUEST ===")
	print("Start: ", start, " End: ", end, " agent_full_size: ", agent_full_size, " mask: ", mask)
	print("Total obstacles: ", system.obstacles.size())
	
	# Log all obstacle positions and states
	var world_poly
	for i in range(system.obstacles.size()):
		var obs: PathfinderObstacle = system.obstacles[i]
		world_poly = obs.get_world_polygon()
		print("Obstacle ", i, ": pos=", obs.global_position, " static=", obs.is_static, " poly=", world_poly)
		obs.system.array_pool.return_packedVector2_array(world_poly)
	
	if PathfindingUtils.is_safe_circle_path(system, start, end, agent_full_size, mask):
		print("Using direct path")
		return PackedVector2Array([start, end])
	
	var start_grid = PathfindingUtils.find_safe_circle_position(system, start, agent_full_size, mask)
	var end_grid = PathfindingUtils.find_safe_circle_position(system, end, agent_full_size, mask)
	
	print("Start grid pos: ", start_grid, " (safe: ", start_grid != Vector2.INF, ")")
	print("End grid pos: ", end_grid, " (safe: ", end_grid != Vector2.INF, ")")
	
	if start_grid == Vector2.INF or end_grid == Vector2.INF:
		print("No safe grid positions found - PATH BLOCKED")
		return PackedVector2Array()
	
	var path = system.astar_pathfinding.a_star_pathfind_circle(start_grid, end_grid, agent_full_size, mask)
	
	# coneection to last point
	if path.size() > 0 and path[-1].distance_to(end) > agent_full_size:
		if PathfindingUtils.is_safe_circle_path(system, path[-1], end, agent_full_size, mask):
			path.append(end)
	
	print("A* result: ", path.size(), " waypoints")
	
	if path.size() > 2:
		path = PathfindingUtils.smooth_circle_path(system, path, agent_full_size, mask)
		print("Smoothed to: ", path.size(), " waypoints")
	
	system.astar_pathfinding.cleanup_path_nodes()

	print("=== END PATHFINDING REQUEST ===")
	return path
