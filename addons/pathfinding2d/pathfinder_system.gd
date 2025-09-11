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
@export var pathfinders: Array[PathfinderAgent] = []
@export var obstacles: Array[PathfinderObstacle] = []

@export_group("PathNode Pool Settings")
@export var pool_size: int = 100
@export var pool_allow_expand: bool = true
@export var pool_expand_step: int = 20

@export_group("Array Pool Settings")
@export var array_pool_size: int = 50
@export var array_pool_allow_expand: bool = true
@export var array_pool_expand_step: int = 10

@export_group("Spatial Partitioning")
## Smaller = more precise spatial filtering = better performance, but takes more memory. (Restart required)
@export var sector_size_multiplier: float = 4.0
## Objects per QuadTree node before splitting. Lower = faster queries, more memory. (Restart required)
@export var quadtree_max_objects: int = 10
## Maximum QuadTree subdivision depth. Higher = faster queries in dense areas. (Restart required)
@export var quadtree_max_levels: int = 5

@export_group("Batch Update Settings")
## Frame rate for processing batched updates. Higher = more responsive to obstacle changes but uses more CPU. Lower = less responsive but better performance. Only if obstacles move very fast and you need instant path reactions. For most games, even 30fps batching is perfectly fine. (Restart required)
@export var batch_update_fps: int = 30

var spatial_partition: SpatialPartition
var grid_manager: GridManager
var obstacle_manager: ObstacleManager
var astar_pathfinding: AStarPathfinding
var path_node_pool: PathNodePool
var array_pool: GenericArrayPool
var batch_manager: BatchUpdateManager
var request_queue: PathfindingRequestQueue

func _ready():
	path_node_pool = PathNodePool.new(pool_size, pool_allow_expand, pool_expand_step)
	array_pool = GenericArrayPool.new(array_pool_size, array_pool_allow_expand, array_pool_expand_step)
	
	grid_manager = GridManager.new(self)
	obstacle_manager = ObstacleManager.new(self)
	astar_pathfinding = AStarPathfinding.new(self, path_node_pool)
	batch_manager = BatchUpdateManager.new(self, batch_update_fps)
	spatial_partition = SpatialPartition.new(self, grid_size * sector_size_multiplier, quadtree_max_objects, quadtree_max_levels)
	request_queue = PathfindingRequestQueue.new(self, 3, 5.0)
	
	if not Engine.is_editor_hint():
		_initialize_system()

func _physics_process(delta: float) -> void:
	if not Engine.is_editor_hint():
		batch_manager.process_frame(delta)
		request_queue.process_queue()

func _initialize_system():
	_register_initial_pathfinders()
	_register_initial_obstacles()
	grid_manager.build_grid()

func _register_initial_pathfinders() -> void:
	for pathfinder in pathfinders:
		_prepare_registered_pathfinder(pathfinder)

# unregister in obstacle_manager
func _register_initial_obstacles() -> void:
	print("=== INITIAL OBSTACLES BOUNDS ===")
	for i in range(obstacles.size()):
		var obstacle = obstacles[i]
		if not is_instance_valid(obstacle):
			continue
		obstacle.system = self
		var world_poly = obstacle.get_world_polygon()
		var bounds = PathfindingUtils.get_polygon_bounds(world_poly)
		array_pool.return_packedVector2_array(world_poly)
		print("Obstacle ", i, ": pos=", obstacle.global_position, " bounds=", bounds, " static=", obstacle.is_static)
		obstacle_manager.register_initial_obstacle(obstacle)
	print("=== END INITIAL OBSTACLES ===")

func _invalidate_affected_paths():
	for pathfinder in pathfinders:
		if pathfinder.is_moving and not PathfindingUtils.is_path_safe(pathfinder.system, pathfinder.current_path, pathfinder.global_position, pathfinder.path_index, pathfinder.agent_full_size, pathfinder.mask):
			pathfinder._recalculate_or_find_alternative()

func register_pathfinder(pathfinder: PathfinderAgent):
	if pathfinder not in pathfinders:
		pathfinders.append(pathfinder)
	
	_prepare_registered_pathfinder(pathfinder)

func _prepare_registered_pathfinder(pathfinder: PathfinderAgent):
	pathfinder.system = self
	spatial_partition.add_agent(pathfinder)

func unregister_pathfinder(pathfinder: PathfinderAgent):
	pathfinders.erase(pathfinder)
	pathfinder.system = null
	spatial_partition.remove_agent(pathfinder)

# Find the closest safe point outside all obstacles for a given unsafe position
func _find_closest_safe_point(unsafe_pos: Vector2, agent_full_size: float, mask: int) -> Vector2:
	# First, find which obstacle(s) contain this point
	var containing_obstacles: Array[PathfinderObstacle] = array_pool.get_obstacle_array()
	var nearby_obstacles = spatial_partition.get_obstacles_near_point(unsafe_pos, agent_full_size + PathfindingConstants.CLEARANCE_BASE_ADDITION)
	for obstacle in nearby_obstacles:
		if is_instance_valid(obstacle) and obstacle.is_point_inside(unsafe_pos):
			containing_obstacles.append(obstacle)
	
	# Point is not actually inside an obstacle, check if it's just too close
	if containing_obstacles.is_empty():
		print("Point not inside obstacle, finding safe position nearby...")
		array_pool.return_obstacles_array(containing_obstacles)
		return astar_pathfinding._find_safe_circle_position(unsafe_pos, agent_full_size, mask)
	
	print("Point is inside ", containing_obstacles.size(), " obstacle(s)")
	
	# For each containing obstacle, find multiple candidate points
	var candidates: Array[Vector2] = array_pool.get_vector2_array()
	
	for obstacle in containing_obstacles:
		var safe_pos = _find_closest_point_outside_obstacle(unsafe_pos, obstacle, agent_full_size, mask)
		if safe_pos != Vector2.INF:
			candidates.append(safe_pos)
		
		# Also try finding safe points in cardinal directions from obstacle edges
		var world_poly = obstacle.get_world_polygon()
		var poly_center = PathfindingUtils.get_polygon_center(world_poly)
		array_pool.return_packedVector2_array(world_poly)
		var directions = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
		
		for direction in directions:
			var test_distance: float = (agent_full_size + PathfindingConstants.FALLBACK_SEARCH_BUFFER)  # Generous distance
			var candidate: Vector2 = unsafe_pos + direction * test_distance
			
			if PathfindingUtils.is_point_in_polygon(candidate, bounds_polygon) and \
			   not PathfindingUtils.is_circle_position_unsafe(self, candidate, agent_full_size, mask):
				candidates.append(candidate)
	
	array_pool.return_obstacles_array(containing_obstacles)
	
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
		array_pool.return_vector2_array(candidates)
		return best_candidate
	
	# Fallback: search in expanding circles with larger steps
	print("Using enhanced fallback search method...")
	var search_step: int = int(max(grid_size, agent_full_size + PathfindingConstants.ENHANCED_SEARCH_STEP_BUFFER))  # Larger search steps
	var max_search_radius: int = int(max(grid_size * PathfindingConstants.CLEARANCE_BASE_ADDITION, agent_full_size * PathfindingConstants.CLEARANCE_SAFETY_MARGIN))  # Expanded search area
	
	# Try positions in expanding circles around target
	for search_radius in range(search_step, max_search_radius, search_step):
		for angle in range(0, int(TAU / PathfindingConstants.ENHANCED_SEARCH_ANGLE_STEP)):
			var test_angle = angle * PathfindingConstants.ENHANCED_SEARCH_ANGLE_STEP
			var offset = Vector2(cos(test_angle), sin(test_angle)) * search_radius
			var test_pos = unsafe_pos + offset
			
			# Must be within bounds and not unsafe
			if PathfindingUtils.is_point_in_polygon(test_pos, bounds_polygon) and \
			   not PathfindingUtils.is_circle_position_unsafe(self, test_pos, agent_full_size, mask):
				print("Fallback found safe point at: ", test_pos)
				array_pool.return_vector2_array(candidates)
				return test_pos
	
	print("Could not find any safe point!")
	array_pool.return_vector2_array(candidates)
	return Vector2.INF

func _find_closest_point_outside_obstacle(point: Vector2, obstacle: PathfinderObstacle, agent_full_size: float, mask: int) -> Vector2:
	"""Find closest point outside a specific obstacle with better clearance"""
	var world_poly = obstacle.get_world_polygon()
	if world_poly.is_empty():
		array_pool.return_packedVector2_array(world_poly)
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
		var edge_point = PathfindingUtils.closest_point_on_line_segment(point, edge_start, edge_end)
		
		# Calculate outward direction from obstacle
		var direction = (point - edge_point).normalized()
		if direction.length() < PathfindingConstants.MIN_DIRECTION_LENGTH:  # Handle case where point is exactly on edge
			# Use edge normal instead
			var edge_vector = (edge_end - edge_start).normalized()
			direction = Vector2(-edge_vector.y, edge_vector.x)  # Perpendicular (outward)
			
			# Determine which side is "outward" by testing
			var test_point1 = edge_point + direction * PathfindingConstants.DIRECTION_TEST_DISTANCE
			var test_point2 = edge_point - direction * PathfindingConstants.DIRECTION_TEST_DISTANCE
			
			if PathfindingUtils.is_point_in_polygon(test_point1, world_poly):
				direction = -direction  # Flip if we picked the wrong direction
		
		# Try multiple clearance distances for robustness
		var clearance_distances = []
		for multiplier in PathfindingConstants.CLEARANCE_MULTIPLIERS:
			clearance_distances.append(base_clearance + PathfindingConstants.CLEARANCE_SAFETY_MARGIN * multiplier)
		
		for clearance_distance in clearance_distances:
			var safe_candidate = edge_point + direction * clearance_distance
			
			# Verify this candidate is good
			if PathfindingUtils.is_point_in_polygon(safe_candidate, bounds_polygon) and \
			   not PathfindingUtils.is_circle_position_unsafe(self, safe_candidate, agent_full_size, mask):
				var distance = point.distance_to(safe_candidate)
				if distance < closest_distance:
					closest_distance = distance
					closest_point = safe_candidate
					break  # Found a good point, stop trying further distances
	
	# If no edge-based solution worked, try radial approach with multiple distances
	if closest_point == Vector2.INF:
		print("Edge-based approach failed, trying radial approach...")
		var poly_center = PathfindingUtils.get_polygon_center(world_poly)
		array_pool.return_packedVector2_array(world_poly)
		var direction = (point - poly_center).normalized()
		
		# Try progressively larger distances
		var test_distances = []
		for multiplier in PathfindingConstants.CLEARANCE_MULTIPLIERS:
			test_distances.append(base_clearance + PathfindingConstants.CLEARANCE_SAFETY_MARGIN * multiplier)
		
		for dist in test_distances:
			var candidate = point + direction * dist
			if PathfindingUtils.is_point_in_polygon(candidate, bounds_polygon) and \
			   not PathfindingUtils.is_circle_position_unsafe(self, candidate, agent_full_size, mask):
				print("Radial approach found safe point at distance: ", dist)
				return candidate
		
		# Last resort: try 8 cardinal directions from the point
		print("Trying cardinal directions as last resort...")
		var directions = PathfindingConstants.CARDINAL_DIRECTIONS + PathfindingConstants.DIAGONAL_DIRECTIONS
		
		for dir in directions:
			for dist in test_distances:
				var candidate = point + dir * dist
				if PathfindingUtils.is_point_in_polygon(candidate, bounds_polygon) and \
				   not PathfindingUtils.is_circle_position_unsafe(self, candidate, agent_full_size, mask):
					print("Cardinal direction found safe point: ", candidate)
					return candidate
	
	array_pool.return_packedVector2_array(world_poly)
	return closest_point
