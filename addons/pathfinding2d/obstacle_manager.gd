@tool
extends RefCounted
class_name ObstacleManager

var system: PathfinderSystem
var cache_manager: CacheManager
var pending_static_changes: Array[PathfinderObstacle] = []
var batch_timer: float = 0.0
var batch_interval: float = PathfindingConstants.BATCH_PROCESSING_INTERVAL
var dynamic_obstacles: Array[PathfinderObstacle] = []

func _init(pathfinder_system: PathfinderSystem):
	system = pathfinder_system
	cache_manager = CacheManager.new()

func update_system(delta: float):
	cache_manager.update_cache(delta, system.obstacles + dynamic_obstacles)
	batch_timer += delta
	 
	if batch_timer >= batch_interval and not pending_static_changes.is_empty():
		_process_batched_static_changes()
		batch_timer = 0.0
	 
	_lazy_cleanup_obstacles()

func register_obstacle(obstacle: PathfinderObstacle):
	if obstacle in system.obstacles:
		return
	
	system.obstacles.append(obstacle)
	_prepare_registered_obstacle(obstacle)

func unregister_obstacle(obstacle: PathfinderObstacle):
	system.obstacles.erase(obstacle)
	dynamic_obstacles.erase(obstacle)
	obstacle.system = null
	
	if obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
		obstacle.obstacle_changed.disconnect(_on_obstacle_changed)
	if obstacle.static_state_changed.is_connected(_on_obstacle_static_changed):
		obstacle.static_state_changed.disconnect(_on_obstacle_static_changed)

func get_pathfinders_affected_by_obstacle(obstacle: PathfinderObstacle) -> Array[Pathfinder]:
	"""Get pathfinders whose paths might be affected by this obstacle"""
	var affected: Array[Pathfinder] = system.vector2_array_pool.get_pathfinder_array()
	var world_poly = obstacle.get_world_polygon()
	var obstacle_bounds = PathfindingUtils.get_polygon_bounds(world_poly)
	
	# Expand bounds to account for agent sizes
	obstacle_bounds = obstacle_bounds.grow(PathfindingConstants.BOUNDS_EXPANSION_CONSERVATIVE)  # Conservative expansion
	
	for pathfinder in system.pathfinders:
		if not is_instance_valid(pathfinder) or not pathfinder.is_moving:
			continue
		
		# Check if pathfinder's current path intersects obstacle area
		var path = pathfinder.get_current_path()
		var path_intersects = false
		
		# Check if any remaining waypoints are in the obstacle area
		for i in range(pathfinder.path_index, path.size()):
			if obstacle_bounds.has_point(path[i]):
				path_intersects = true
				break
		
		# Check if any remaining path segments cross the obstacle area
		if not path_intersects:
			for i in range(pathfinder.path_index, path.size() - 1):
				var segment_start = path[i]
				var segment_end = path[i + 1]
				
				# Create bounding box for this segment
				var segment_bounds = Rect2()
				segment_bounds = segment_bounds.expand(segment_start)
				segment_bounds = segment_bounds.expand(segment_end)
				
				if segment_bounds.intersects(obstacle_bounds):
					path_intersects = true
					break
		
		if path_intersects:
			affected.append(pathfinder)
	
	return affected

func _get_valid_dynamic_obstacles() -> Array[PathfinderObstacle]:
	"""Get filtered valid dynamic obstacles (cached)"""
	return cache_manager.get_cached_valid_items(dynamic_obstacles)

func _prepare_registered_obstacle(obstacle: PathfinderObstacle):
	obstacle.system = system
	if not obstacle.is_static and obstacle not in dynamic_obstacles:
		dynamic_obstacles.append(obstacle)
	if not obstacle.is_static:
		if not obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
			obstacle.obstacle_changed.connect(_on_obstacle_changed)
	if not obstacle.static_state_changed.is_connected(_on_obstacle_static_changed):
		obstacle.static_state_changed.connect(_on_obstacle_static_changed.bind(obstacle))

func _is_obstacle_valid_cached(obstacle: PathfinderObstacle) -> bool:
	"""Get cached validity or fallback to real check"""
	return cache_manager.is_item_valid_cached(obstacle)

func _lazy_cleanup_obstacles():
	"""Remove invalid obstacles only when needed, not immediately"""
	if cache_manager.validity_cache.is_empty():
		return
	system.obstacles = cache_manager.remove_invalid_items(system.obstacles)
	dynamic_obstacles = cache_manager.remove_invalid_items(dynamic_obstacles)

func _process_batched_static_changes():
	"""Process multiple static/dynamic state changes in one batch"""
	print("Processing ", pending_static_changes.size(), " batched static changes")
	
	var became_static = 0
	var became_dynamic = 0
	
	for obstacle in pending_static_changes:
		if not _is_obstacle_valid_cached(obstacle):
			continue
			
		if obstacle.is_static:
			# Became static - remove from dynamic list
			if obstacle in dynamic_obstacles:
				dynamic_obstacles.erase(obstacle)
				became_static += 1
				if obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
					obstacle.obstacle_changed.disconnect(_on_obstacle_changed)
		else:
			# Became dynamic - add to dynamic list
			if obstacle not in dynamic_obstacles:
				dynamic_obstacles.append(obstacle)
				became_dynamic += 1
				if not obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
					obstacle.obstacle_changed.connect(_on_obstacle_changed)
	
	if became_static > 0 or became_dynamic > 0:
		print("Batch processed: ", became_static, " became static, ", became_dynamic, " became dynamic")
		system.grid_dirty = true  # Trigger grid update after batch
	
	pending_static_changes.clear()

func _on_obstacle_static_changed(is_now_static: bool, obstacle: PathfinderObstacle):
	"""Queue static/dynamic state changes for batch processing"""
	if obstacle not in pending_static_changes:
		pending_static_changes.append(obstacle)
	
	# For immediate critical cases, still process right away
	if pending_static_changes.size() > PathfindingConstants.MAX_BATCH_SIZE:  # Prevent queue from getting too large
		_process_batched_static_changes()

func _on_obstacle_changed():
	print("=== OBSTACLE CHANGED EVENT ===")
	
	# Find which obstacle actually changed by checking all dynamic obstacles
	var changed_obstacle = null
	for obstacle in dynamic_obstacles:
		if is_instance_valid(obstacle) and obstacle._has_changed():
			changed_obstacle = obstacle
			break
	
	if not changed_obstacle:
		print("No changed obstacle found - skipping update")
		return
	
	print("Changed obstacle at: ", changed_obstacle.global_position)
	
	# Update grid only around the changed obstacle
	system.grid_manager.update_grid_around_obstacle(changed_obstacle)
	
	# Only invalidate paths that actually intersect with this obstacle
	var affected_pathfinders = get_pathfinders_affected_by_obstacle(changed_obstacle)
	print("Affecting ", affected_pathfinders.size(), " pathfinders")
	
	for pathfinder in affected_pathfinders:
		if pathfinder.is_moving:
			print("Invalidating path for pathfinder at: ", pathfinder.global_position)
			pathfinder.consecutive_failed_recalcs = 0
			pathfinder.call_deferred("_recalculate_or_find_alternative")
			
	system.vector2_array_pool.return_pathfinder_array(affected_pathfinders)
	print("=== END OBSTACLE CHANGED ===")
