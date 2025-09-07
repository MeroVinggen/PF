@tool
extends RefCounted
class_name SpatialPartition

var system: PathfinderSystem
var sector_size: float
var sectors: Dictionary = {}  # Vector2i -> Array[PathfinderObstacle]

func _init(pathfinder_system: PathfinderSystem, size: float = 100.0):
	system = pathfinder_system
	sector_size = size

func add_obstacle(obstacle: PathfinderObstacle):
	var sectors_occupied = _get_obstacle_sectors(obstacle)
	for sector_coord in sectors_occupied:
		if not sectors.has(sector_coord):
			sectors[sector_coord] = []
		if obstacle not in sectors[sector_coord]:
			sectors[sector_coord].append(obstacle)

func remove_obstacle(obstacle: PathfinderObstacle):
	for sector_coord in sectors.keys():
		sectors[sector_coord].erase(obstacle)
		if sectors[sector_coord].is_empty():
			sectors.erase(sector_coord)

func update_obstacle(obstacle: PathfinderObstacle):
	remove_obstacle(obstacle)
	add_obstacle(obstacle)

func get_obstacles_in_region(min_pos: Vector2, max_pos: Vector2) -> Array[PathfinderObstacle]:
	var result: Array[PathfinderObstacle] = []
	var visited: Dictionary = {}
	
	var min_sector = _world_to_sector(min_pos)
	var max_sector = _world_to_sector(max_pos)
	
	for x in range(min_sector.x, max_sector.x + 1):
		for y in range(min_sector.y, max_sector.y + 1):
			var sector_coord = Vector2i(x, y)
			if sectors.has(sector_coord):
				for obstacle in sectors[sector_coord]:
					if not visited.has(obstacle):
						visited[obstacle] = true
						result.append(obstacle)
	
	return result

func get_obstacles_near_point(pos: Vector2, radius: float) -> Array[PathfinderObstacle]:
	var min_pos = pos - Vector2(radius, radius)
	var max_pos = pos + Vector2(radius, radius)
	return get_obstacles_in_region(min_pos, max_pos)

func _get_obstacle_sectors(obstacle: PathfinderObstacle) -> Array[Vector2i]:
	var world_poly = obstacle.get_world_polygon()
	if world_poly.is_empty():
		return []
	
	var bounds = PathfindingUtils.get_polygon_bounds(world_poly)
	var min_sector = _world_to_sector(bounds.position)
	var max_sector = _world_to_sector(bounds.position + bounds.size)
	
	var result: Array[Vector2i] = []
	for x in range(min_sector.x, max_sector.x + 1):
		for y in range(min_sector.y, max_sector.y + 1):
			result.append(Vector2i(x, y))
	
	return result

func _world_to_sector(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / sector_size)),
		int(floor(world_pos.y / sector_size))
	)
