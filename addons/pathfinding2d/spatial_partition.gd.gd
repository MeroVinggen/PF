@tool
extends RefCounted
class_name SpatialPartition

var system: PathfinderSystem
var sector_size: float
# typing: Vector2i -> Array[PathfinderObstacle]
var sectors: Dictionary = {}  
# Vector2i -> Array[PathfinderAgent]
var agent_sectors: Dictionary = {}
var max_objects: int
var max_levels: int

func _init(pathfinder_system: PathfinderSystem, size: float = 100.0, max_objs: int = 10, max_lvls: int = 5):
	system = pathfinder_system
	sector_size = size
	max_objects = max_objs
	max_levels = max_lvls

func add_obstacle(obstacle: PathfinderObstacle):
	var sectors_occupied = _get_obstacle_sectors(obstacle)
	for sector_coord in sectors_occupied:
		if not sectors.has(sector_coord):
			var sector_bounds = _get_sector_bounds(sector_coord)
			sectors[sector_coord] = QuadTree.new(system, sector_bounds, max_objects, max_levels)
		sectors[sector_coord].insert(obstacle)
	system.array_pool.return_vector2i_array(sectors_occupied)

func remove_obstacle(obstacle: PathfinderObstacle):
	# Rebuild affected sectors (simpler than complex removal)
	var sectors_occupied = _get_obstacle_sectors(obstacle)
	for sector_coord in sectors_occupied:
		if sectors.has(sector_coord):
			_rebuild_sector(sector_coord)
	system.array_pool.return_vector2i_array(sectors_occupied)

func update_obstacle(obstacle: PathfinderObstacle):
	remove_obstacle(obstacle)
	add_obstacle(obstacle)

func add_agent(agent: PathfinderAgent):
	var sectors_occupied = _get_agent_sectors(agent)
	for sector_coord in sectors_occupied:
		if not agent_sectors.has(sector_coord):
			agent_sectors[sector_coord] = []
		if agent not in agent_sectors[sector_coord]:
			agent_sectors[sector_coord].append(agent)
	system.array_pool.return_vector2i_array(sectors_occupied)

func remove_agent(agent: PathfinderAgent):
	var sectors_occupied = _get_agent_sectors(agent)
	for sector_coord in sectors_occupied:
		if agent_sectors.has(sector_coord):
			agent_sectors[sector_coord].erase(agent)
			if agent_sectors[sector_coord].is_empty():
				agent_sectors.erase(sector_coord)
	system.array_pool.return_vector2i_array(sectors_occupied)

func update_agent(agent: PathfinderAgent):
	remove_agent(agent)
	add_agent(agent)

func get_obstacles_in_region(min_pos: Vector2, max_pos: Vector2) -> Array[PathfinderObstacle]:
	# will be released in usage places
	var result: Array[PathfinderObstacle] = system.array_pool.get_obstacle_array()
	var visited: Dictionary = {}
	var query_bounds = Rect2(min_pos, max_pos - min_pos)
	
	var min_sector = _world_to_sector(min_pos)
	var max_sector = _world_to_sector(max_pos)
	
	for x in range(min_sector.x, max_sector.x + 1):
		for y in range(min_sector.y, max_sector.y + 1):
			var sector_coord = Vector2i(x, y)
			if sectors.has(sector_coord):
				var sector_obstacles = sectors[sector_coord].get_obstacles_in_bounds(query_bounds)
				for obstacle in sector_obstacles:
					if not visited.has(obstacle):
						visited[obstacle] = true
						result.append(obstacle)
				system.array_pool.return_obstacles_array(sector_obstacles)
	
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
	system.array_pool.return_packedVector2_array(world_poly)
	
	var result: Array[Vector2i] = system.array_pool.get_vector2i_array()
	for x in range(min_sector.x, max_sector.x + 1):
		for y in range(min_sector.y, max_sector.y + 1):
			result.append(Vector2i(x, y))
	
	return result

func _get_sectors_in_radius(center_pos: Vector2, radius: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = system.array_pool.get_vector2i_array()
	
	# Calculate bounding box of the radius
	var min_pos = center_pos - Vector2(radius, radius)
	var max_pos = center_pos + Vector2(radius, radius)
	
	var min_sector = _world_to_sector(min_pos)
	var max_sector = _world_to_sector(max_pos)
	
	# Add all sectors in the bounding box
	for x in range(min_sector.x, max_sector.x + 1):
		for y in range(min_sector.y, max_sector.y + 1):
			result.append(Vector2i(x, y))
	
	return result

func get_agents_near_obstacle_and_trigger_path_recalc(obstacle: PathfinderObstacle) -> void:
	var obstacle_sectors = _get_sectors_in_radius(obstacle.global_position, obstacle.cached_max_radius)
	var visited: Dictionary = {}
	
	for sector_coord in obstacle_sectors:
		if agent_sectors.has(sector_coord):
			for agent in agent_sectors[sector_coord]:
				if visited.has(agent):
					continue
				
				visited[agent] = true
				
				# filter by layer and idle agents
				if (agent.mask & obstacle.layer) == 0 or not agent.is_moving:
					continue
				
				# filter by distance (partition sectors are too big)
				if agent.global_position.distance_to(obstacle.global_position) >= obstacle.cached_max_radius + agent.agent_radius + agent.agent_buffer + 5:
					continue
				
				agent._recalculate_or_find_alternative()
	system.array_pool.return_vector2i_array(obstacle_sectors)

func _get_agent_sectors(agent: PathfinderAgent) -> Array[Vector2i]:
	var result: Array[Vector2i] = system.array_pool.get_vector2i_array()
	var agent_pos = agent.global_position
	var agent_radius = agent.agent_radius + agent.agent_buffer
	
	# Get sectors that the agent's collision circle overlaps
	var min_pos = agent_pos - Vector2(agent_radius, agent_radius)
	var max_pos = agent_pos + Vector2(agent_radius, agent_radius)
	
	var min_sector = _world_to_sector(min_pos)
	var max_sector = _world_to_sector(max_pos)
	
	for x in range(min_sector.x, max_sector.x + 1):
		for y in range(min_sector.y, max_sector.y + 1):
			result.append(Vector2i(x, y))
	
	return result

func _world_to_sector(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / sector_size)),
		int(floor(world_pos.y / sector_size))
	)

func _get_sector_bounds(sector_coord: Vector2i) -> Rect2:
	var x = sector_coord.x * sector_size
	var y = sector_coord.y * sector_size
	return Rect2(x, y, sector_size, sector_size)

func _rebuild_sector(sector_coord: Vector2i):
	if not sectors.has(sector_coord):
		return
	
	var sector_bounds = _get_sector_bounds(sector_coord)
	sectors[sector_coord].clear()
	
	# Re-add all obstacles in this sector
	for obstacle in system.obstacles:
		var obstacle_sectors = _get_obstacle_sectors(obstacle)
		if sector_coord in obstacle_sectors:
			sectors[sector_coord].insert(obstacle)	
		system.array_pool.return_vector2i_array(obstacle_sectors)
