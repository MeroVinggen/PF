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
@export var dynamic_update_rate: float = 0.1
@export var auto_invalidate_paths: bool = true
@export var pathfinders: Array[Pathfinder] = []
@export var obstacles: Array[PathfinderObstacle] = []

@onready var shared_validator: PathValidator = PathValidator.new(self)

var grid_dirty: bool = false
var last_grid_update: float = 0.0
var path_invalidation_timer: float = 0.0

# Manager components
var grid_manager: GridManager
var obstacle_manager: ObstacleManager
var astar_pathfinding: AStarPathfinding

func _ready():
	# Initialize managers
	grid_manager = GridManager.new(self)
	obstacle_manager = ObstacleManager.new(self)
	astar_pathfinding = AStarPathfinding.new(self)
	
	if not Engine.is_editor_hint():
		_initialize_system()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_dynamic_system(delta)

func _update_dynamic_system(delta):
	last_grid_update += delta
	path_invalidation_timer += delta
	
	# Update obstacle manager
	obstacle_manager.update_system(delta)
	
	var should_update_grid = grid_dirty and last_grid_update >= dynamic_update_rate
	var should_invalidate_paths = auto_invalidate_paths and path_invalidation_timer >= dynamic_update_rate * 2
	
	if should_update_grid:
		grid_manager.update_grid_for_dynamic_obstacles()
		grid_dirty = false
		last_grid_update = 0.0
	
	if should_invalidate_paths and not obstacle_manager._get_valid_dynamic_obstacles().is_empty():
		_invalidate_affected_paths()
		path_invalidation_timer = 0.0

func _initialize_system():
	_register_initial_pathfinders()
	_register_initial_obstacles()
	grid_manager.build_grid()

func _register_initial_pathfinders() -> void:
	for pathfinder in pathfinders:
		_prepare_registered_pathfinder(pathfinder)

func _register_initial_obstacles() -> void:
	for obstacle in obstacles:
		obstacle_manager.register_obstacle(obstacle)

func _invalidate_affected_paths():
	for pathfinder in pathfinders:
		if is_instance_valid(pathfinder) and pathfinder.is_moving and not pathfinder.is_path_valid():
			pathfinder.recalculate_path()

func register_obstacle(obstacle: PathfinderObstacle):
	obstacle_manager.register_obstacle(obstacle)

func unregister_obstacle(obstacle: PathfinderObstacle):
	obstacle_manager.unregister_obstacle(obstacle)

func register_pathfinder(pathfinder: Pathfinder):
	if pathfinder not in pathfinders:
		pathfinders.append(pathfinder)
	
	_prepare_registered_pathfinder(pathfinder)

func _prepare_registered_pathfinder(pathfinder: Pathfinder):
	pathfinder.system = self
	pathfinder.validator = shared_validator

func unregister_pathfinder(pathfinder: Pathfinder):
	pathfinders.erase(pathfinder)
	pathfinder.system = null

func find_path_for_circle(start: Vector2, end: Vector2, radius: float, buffer: float = 2.0) -> PackedVector2Array:
	return astar_pathfinding.find_path_for_circle(start, end, radius, buffer)

# Utility functions for other components
func get_dynamic_obstacle_count() -> int:
	return obstacle_manager._get_valid_dynamic_obstacles().size()

func is_grid_dirty() -> bool:
	return grid_dirty

func force_grid_update():
	if obstacle_manager.dynamic_obstacles.size() > 0:
		grid_manager.update_grid_for_dynamic_obstacles()
		grid_dirty = false
		last_grid_update = 0.0

# Methods used by PathValidator
func _is_circle_position_unsafe(pos: Vector2, radius: float, buffer: float) -> bool:
	return astar_pathfinding._is_circle_position_unsafe(pos, radius, buffer)

func _is_safe_circle_path(start: Vector2, end: Vector2, radius: float, buffer: float) -> bool:
	return astar_pathfinding._is_safe_circle_path(start, end, radius, buffer)

func _find_closest_safe_point(unsafe_pos: Vector2, radius: float, buffer: float) -> Vector2:
	"""Find the closest safe point outside all obstacles for a given unsafe position"""
	
	# First, find which obstacle(s) contain this point
	var containing_obstacles: Array[PathfinderObstacle] = []
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.is_point_inside(unsafe_pos):
			containing_obstacles.append(obstacle)
	
	if containing_obstacles.is_empty():
		# Point is not actually inside an obstacle, check if it's just too close
		print("Point not inside obstacle, finding safe position nearby...")
		return astar_pathfinding._find_safe_circle_position(unsafe_pos, radius, buffer)
	
	print("Point is inside ", containing_obstacles.size(), " obstacle(s)")
	
	# For each containing obstacle, find multiple candidate points
	var candidates: Array[Vector2] = []
	
	for obstacle in containing_obstacles:
		var safe_pos = _find_closest_point_outside_obstacle(unsafe_pos, obstacle, radius, buffer)
		if safe_pos != Vector2.INF:
			candidates.append(safe_pos)
		
		# Also try finding safe points in cardinal directions from obstacle edges
		var world_poly = obstacle.get_world_polygon()
		var poly_center = PathfindingUtils.get_polygon_center(world_poly)
		var directions = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
		
		for direction in directions:
			var test_distance: float = (radius + buffer + PathfindingConstants.FALLBACK_SEARCH_BUFFER)  # Generous distance
			var candidate: Vector2 = unsafe_pos + direction * test_distance
			
			if PathfindingUtils.is_point_in_polygon(candidate, bounds_polygon) and \
			   not _is_circle_position_unsafe(candidate, radius, buffer):
				candidates.append(candidate)
	
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
		return best_candidate
	
	# Fallback: search in expanding circles with larger steps
	print("Using enhanced fallback search method...")
	var search_step: int = int(max(grid_size, radius + buffer + PathfindingConstants.ENHANCED_SEARCH_STEP_BUFFER))  # Larger search steps
	var max_search_radius: int = int(max(grid_size * PathfindingConstants.CLEARANCE_BASE_ADDITION, radius * PathfindingConstants.CLEARANCE_SAFETY_MARGIN))  # Expanded search area
	
	# Try positions in expanding circles around target
	for search_radius in range(search_step, max_search_radius, search_step):
		for angle in range(0, int(TAU / PathfindingConstants.ENHANCED_SEARCH_ANGLE_STEP)):
			var test_angle = angle * PathfindingConstants.ENHANCED_SEARCH_ANGLE_STEP
			var offset = Vector2(cos(test_angle), sin(test_angle)) * search_radius
			var test_pos = unsafe_pos + offset
			
			# Must be within bounds and not unsafe
			if PathfindingUtils.is_point_in_polygon(test_pos, bounds_polygon) and \
			   not _is_circle_position_unsafe(test_pos, radius, buffer):
				print("Fallback found safe point at: ", test_pos)
				return test_pos
	
	print("Could not find any safe point!")
	return Vector2.INF

func _find_closest_point_outside_obstacle(point: Vector2, obstacle: PathfinderObstacle, radius: float, buffer: float) -> Vector2:
	"""Find closest point outside a specific obstacle with better clearance"""
	var world_poly = obstacle.get_world_polygon()
	if world_poly.is_empty():
		return Vector2.INF
	
	var closest_point = Vector2.INF
	var closest_distance = INF
	
	# Increase clearance distance significantly for better pathfinding success
	var base_clearance: float = radius + buffer + PathfindingConstants.CLEARANCE_BASE_ADDITION  # Increased base clearance
	
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
			   not _is_circle_position_unsafe(safe_candidate, radius, buffer):
				var distance = point.distance_to(safe_candidate)
				if distance < closest_distance:
					closest_distance = distance
					closest_point = safe_candidate
					break  # Found a good point, stop trying further distances
	
	# If no edge-based solution worked, try radial approach with multiple distances
	if closest_point == Vector2.INF:
		print("Edge-based approach failed, trying radial approach...")
		var poly_center = PathfindingUtils.get_polygon_center(world_poly)
		var direction = (point - poly_center).normalized()
		
		# Try progressively larger distances
		var test_distances = []
		for multiplier in PathfindingConstants.CLEARANCE_MULTIPLIERS:
			test_distances.append(base_clearance + PathfindingConstants.CLEARANCE_SAFETY_MARGIN * multiplier)
		
		for dist in test_distances:
			var candidate = point + direction * dist
			if PathfindingUtils.is_point_in_polygon(candidate, bounds_polygon) and \
			   not _is_circle_position_unsafe(candidate, radius, buffer):
				print("Radial approach found safe point at distance: ", dist)
				return candidate
		
		# Last resort: try 8 cardinal directions from the point
		print("Trying cardinal directions as last resort...")
		var directions = PathfindingConstants.CARDINAL_DIRECTIONS + PathfindingConstants.DIAGONAL_DIRECTIONS
		
		for dir in directions:
			for dist in test_distances:
				var candidate = point + dir * dist
				if PathfindingUtils.is_point_in_polygon(candidate, bounds_polygon) and \
				   not _is_circle_position_unsafe(candidate, radius, buffer):
					print("Cardinal direction found safe point: ", candidate)
					return candidate
	
	return closest_point

func _get_configuration_warnings() -> PackedStringArray:
	return PathfindingValidator.validate_pathfinder_system(self)
