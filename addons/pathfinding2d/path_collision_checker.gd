@tool
extends RefCounted
class_name PathCollisionChecker

var system: PathfinderSystem

func _init(pathfinder_system: PathfinderSystem):
	system = pathfinder_system

func is_path_clear(start: Vector2, end: Vector2, radius: float, buffer: float) -> bool:
	var total_radius = radius + buffer
	
	# Get path bounding box
	var path_min = Vector2(min(start.x, end.x), min(start.y, end.y)) - Vector2(total_radius, total_radius)
	var path_max = Vector2(max(start.x, end.x), max(start.y, end.y)) + Vector2(total_radius, total_radius)
	
	# Get obstacles in path region using spatial partition + quadtree
	var path_obstacles = system.spatial_partition.get_obstacles_in_region(path_min, path_max)
	
	# Fast early exit - no obstacles in region
	if path_obstacles.is_empty():
		return true
	
	# Sample path points and check against relevant obstacles only
	var distance = start.distance_to(end)
	var samples = max(int(distance / (system.grid_size * PathfindingConstants.SAMPLE_DISTANCE_FACTOR)), PathfindingConstants.MIN_PATH_SAMPLES)
	
	for i in samples + 1:
		var t = float(i) / float(samples)
		var test_pos = start.lerp(end, t)
		
		if not PathfindingUtils.is_point_in_polygon(test_pos, system.bounds_polygon):
			return false
		
		# Check only relevant obstacles
		for obstacle in path_obstacles:
			if obstacle.disabled:
				continue
			if not ((obstacle.layer & system.current_pathfinder_mask) != 0):
				continue
			
			var world_poly = obstacle.get_world_polygon()
			if world_poly.is_empty():
				continue
				
			var distance_to_obstacle = _distance_point_to_polygon(test_pos, world_poly)
			if distance_to_obstacle < (total_radius - PathfindingConstants.SAFETY_MARGIN):
				return false
	
	return true

func is_position_safe(pos: Vector2, radius: float, buffer: float) -> bool:
	var total_radius = radius + buffer
	
	if not PathfindingUtils.is_point_in_polygon(pos, system.bounds_polygon):
		return false
	
	# Use spatial partition for fast obstacle lookup
	var nearby_obstacles = system.spatial_partition.get_obstacles_near_point(pos, total_radius)
	
	for obstacle in nearby_obstacles:
		if obstacle.disabled:
			continue
		if not ((obstacle.layer & system.current_pathfinder_mask) != 0):
			continue
		
		var world_poly = obstacle.get_world_polygon()
		if world_poly.is_empty():
			continue
			
		var distance_to_obstacle = _distance_point_to_polygon(pos, world_poly)
		if distance_to_obstacle < (total_radius - PathfindingConstants.SAFETY_MARGIN):
			return false
	
	return true

func _distance_point_to_polygon(point: Vector2, polygon: PackedVector2Array) -> float:
	if polygon.is_empty():
		return INF
	
	if PathfindingUtils.is_point_in_polygon(point, polygon):
		return 0.0
	
	var min_distance = INF
	
	for i in polygon.size():
		var edge_start = polygon[i]
		var edge_end = polygon[(i + 1) % polygon.size()]
		var distance = PathfindingUtils.distance_point_to_line_segment(point, edge_start, edge_end)
		min_distance = min(min_distance, distance)
	
	return min_distance
