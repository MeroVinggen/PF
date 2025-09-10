@tool
extends RefCounted
class_name PathValidator

var system: PathfinderSystem

func _init(pathfinder_system: PathfinderSystem):
	system = pathfinder_system

func is_path_safe(path: PackedVector2Array, current_pos: Vector2, path_index: int, agent_full_size: float) -> bool:
	if not system or path.is_empty() or path_index >= path.size():
		return false
	
	# Check current position
	if is_circle_position_unsafe(current_pos, agent_full_size):
		return false
	
	# Check next waypoint
	if path_index < path.size():
		var next_waypoint = path[path_index]
		if is_circle_position_unsafe(next_waypoint, agent_full_size):
			return false
		if not is_safe_circle_path(current_pos, next_waypoint, agent_full_size):
			return false
	
	return true

func is_circle_position_unsafe(pos: Vector2, agent_full_size: float) -> bool:
	#print_stack()
	
	# Use spatial partition instead of system's method
	if not PathfindingUtils.is_point_in_polygon(pos, system.bounds_polygon):
		return true
	
	var nearby_obstacles = system.spatial_partition.get_obstacles_near_point(pos, agent_full_size)
	for obstacle: PathfinderObstacle in nearby_obstacles:
		if obstacle.disabled:
			continue
		if not ((obstacle.layer & system.current_pathfinder_mask) != 0):
			continue
		var world_poly = obstacle.get_world_polygon()
		if world_poly.is_empty():
			system.array_pool.return_packedVector2_array(world_poly)
			continue
			
		var distance_to_obstacle = system.astar_pathfinding._distance_point_to_polygon(pos, world_poly, agent_full_size)
		system.array_pool.return_packedVector2_array(world_poly)
		if distance_to_obstacle < (agent_full_size - PathfindingConstants.SAFETY_MARGIN):
			return true
	
	return false

func is_safe_circle_path(start: Vector2, end: Vector2, agent_full_size: float) -> bool:
	var distance = start.distance_to(end)
	var samples = max(int(distance / (system.grid_size * PathfindingConstants.SAMPLE_DISTANCE_FACTOR)), PathfindingConstants.MIN_PATH_SAMPLES)
	
	# Get obstacles in path region once
	var path_bounds_min = Vector2(min(start.x, end.x), min(start.y, end.y)) - Vector2(agent_full_size, agent_full_size)
	var path_bounds_max = Vector2(max(start.x, end.x), max(start.y, end.y)) + Vector2(agent_full_size, agent_full_size)
	var path_obstacles = system.spatial_partition.get_obstacles_in_region(path_bounds_min, path_bounds_max)
	
	for i in samples + 1:
		var t = float(i) / float(samples)
		var test_pos = start.lerp(end, t)
		
		if _is_position_unsafe_with_obstacles(test_pos, agent_full_size, path_obstacles):
			system.array_pool.return_obstacles_array(path_obstacles)
			return false
	
	system.array_pool.return_obstacles_array(path_obstacles)
	return true

func _is_position_unsafe_with_obstacles(pos: Vector2, agent_full_size: float, obstacles: Array[PathfinderObstacle]) -> bool:
	if not PathfindingUtils.is_point_in_polygon(pos, system.bounds_polygon):
		return true
	
	for obstacle in obstacles:
		if obstacle.disabled:
			continue
		if not ((obstacle.layer & system.current_pathfinder_mask) != 0):
			continue
		var world_poly = obstacle.get_world_polygon()
		if world_poly.is_empty():
			system.array_pool.return_packedVector2_array(world_poly)
			continue
			
		var distance_to_obstacle = system.astar_pathfinding._distance_point_to_polygon(pos, world_poly, agent_full_size)
		system.array_pool.return_packedVector2_array(world_poly)
		if distance_to_obstacle < (agent_full_size - PathfindingConstants.SAFETY_MARGIN):
			return true
	
	return false
