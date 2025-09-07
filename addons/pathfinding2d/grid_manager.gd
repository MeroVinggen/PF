@tool
extends RefCounted
class_name GridManager

var system: PathfinderSystem
var grid: Dictionary = {}

func _init(pathfinder_system: PathfinderSystem):
	system = pathfinder_system

func build_grid():
	grid.clear()
	var bounds = PathfindingUtils.get_polygon_bounds(system.bounds_polygon)
	
	var steps_x = int(bounds.size.x / system.grid_size) + 1
	var steps_y = int(bounds.size.y / system.grid_size) + 1
	
	for i in steps_x:
		for j in steps_y:
			var x = bounds.position.x + (i * system.grid_size)
			var y = bounds.position.y + (j * system.grid_size)
			var pos = Vector2(x, y)
			
			if PathfindingUtils.is_point_in_polygon(pos, system.bounds_polygon):
				grid[pos] = _is_grid_point_clear(pos)

func update_grid_for_dynamic_obstacles():
	if system.obstacle_manager.dynamic_obstacles.is_empty():
		print("No valid dynamic obstacles - skipping grid update")
		return
	
	var affected_bounds = _get_dynamic_obstacles_bounds_cached(system.obstacle_manager.dynamic_obstacles)
	
	if affected_bounds.size.x <= 0 or affected_bounds.size.y <= 0:
		print("Invalid bounds - skipping grid update")
		return
	
	for grid_pos in grid.keys():
		if affected_bounds.has_point(grid_pos):
			grid[grid_pos] = _is_grid_point_clear(grid_pos)

func update_grid_around_obstacle(obstacle: PathfinderObstacle):
	var world_poly = obstacle.get_world_polygon()
	var obstacle_bounds = PathfindingUtils.get_polygon_bounds(world_poly)
	
	# Expand bounds for agent clearance
	obstacle_bounds = obstacle_bounds.grow(system.grid_size * PathfindingConstants.GRID_EXPANSION_FACTOR)
	
	var updated_count = 0
	for grid_pos in grid.keys():
		if obstacle_bounds.has_point(grid_pos):
			var old_value = grid[grid_pos]
			var new_value = _is_grid_point_clear(grid_pos)
			if old_value != new_value:
				grid[grid_pos] = new_value
				updated_count += 1
	
	print("Updated ", updated_count, " grid points around obstacle")

func snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		round(pos.x / system.grid_size) * system.grid_size,
		round(pos.y / system.grid_size) * system.grid_size
	)

func _is_grid_point_clear(pos: Vector2) -> bool:
	for obstacle in system.obstacles:
		if obstacle.disabled:
			continue
		if obstacle.is_point_inside(pos):
			return false
	return true

func _get_dynamic_obstacles_bounds_cached(valid_dynamic: Array[PathfinderObstacle]) -> Rect2:
	if valid_dynamic.is_empty():
		return Rect2()
	
	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)
	
	for obstacle in valid_dynamic:
		var world_poly = obstacle.get_world_polygon()
		for point in world_poly:
			min_pos = min_pos.min(point)
			max_pos = max_pos.max(point)
	
	var buffer = system.grid_size * PathfindingConstants.GRID_BUFFER_FACTOR
	return Rect2(min_pos - Vector2(buffer, buffer), (max_pos - min_pos) + Vector2(buffer * 2, buffer * 2))
