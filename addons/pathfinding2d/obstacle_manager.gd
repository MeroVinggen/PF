@tool
extends RefCounted
class_name ObstacleManager

signal obstacles_changed()

var system: PathfinderSystem
var pending_static_changes: Array[PathfinderObstacle] = []
var dynamic_obstacles: Array[PathfinderObstacle] = []

# additional clean
var cleanup_timer: float = 0.0
const CLEANUP_INTERVAL: float = 1.0

func _init(pathfinder_system: PathfinderSystem):
	system = pathfinder_system

func update_system(delta: float):
	cleanup_timer += delta
	if cleanup_timer >= CLEANUP_INTERVAL:
		_cleanup_invalid_obstacles()
		cleanup_timer = 0.0
	
	if not pending_static_changes.is_empty():
		_process_batched_static_changes()

func _cleanup_invalid_obstacles():
	dynamic_obstacles = dynamic_obstacles.filter(func(obs): return is_instance_valid(obs))

func register_obstacle(obstacle: PathfinderObstacle):
	if obstacle in system.obstacles:
		return
	
	system.obstacles.append(obstacle)
	_prepare_registered_obstacle(obstacle)

func register_initial_obstacle(obstacle) -> void:
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
	# cleanup will happen in caller func 
	var affected: Array[Pathfinder] = system.vector2_array_pool.get_pathfinder_array()
	var world_poly = obstacle.get_world_polygon()
	var obstacle_bounds = PathfindingUtils.get_polygon_bounds(world_poly)
	
	for pathfinder in system.pathfinders:
		if not is_instance_valid(pathfinder) or not pathfinder.is_moving:
			continue
		
		# Check if pathfinder's current path intersects obstacle area
		var path = pathfinder.get_current_path()
		var path_intersects = false
		
		# Check if pathfinder actually conflicts with this obstacle
		if not system.astar_pathfinding._is_safe_circle_path(
			pathfinder.global_position, 
			pathfinder.get_next_waypoint(), 
			pathfinder.agent_radius, 
			pathfinder.agent_buffer
		):
			affected.append(pathfinder)
		
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

func _prepare_registered_obstacle(obstacle: PathfinderObstacle):
	obstacle.system = system
	
	if not obstacle.is_static:
		obstacle.pos_threshold = PathfindingConstants.DYNAMIC_POSITION_THRESHOLD
		obstacle.rot_threshold = PathfindingConstants.DYNAMIC_ROTATION_THRESHOLD
		if obstacle not in dynamic_obstacles:
			dynamic_obstacles.append(obstacle)
		if not obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
			obstacle.obstacle_changed.connect(_on_obstacle_changed)
	else:
		obstacle.pos_threshold = PathfindingConstants.STATIC_POSITION_THRESHOLD
		obstacle.rot_threshold = PathfindingConstants.STATIC_ROTATION_THRESHOLD
	
	if not obstacle.static_state_changed.is_connected(_on_obstacle_static_changed):
		obstacle.static_state_changed.connect(_on_obstacle_static_changed.bind(obstacle))


func _process_batched_static_changes():
	"""Process multiple static/dynamic state changes in one batch"""
	print("Processing ", pending_static_changes.size(), " batched static changes")
	
	var became_static = 0
	var became_dynamic = 0
	
	for obstacle in pending_static_changes:
		if not is_instance_valid(obstacle):
			continue
			
		if obstacle.is_static:
			# Became static - remove from dynamic list
			obstacle.pos_threshold = PathfindingConstants.STATIC_POSITION_THRESHOLD
			obstacle.rot_threshold = PathfindingConstants.STATIC_ROTATION_THRESHOLD
			if obstacle in dynamic_obstacles:
				dynamic_obstacles.erase(obstacle)
				became_static += 1
				if obstacle.obstacle_changed.is_connected(_on_obstacle_changed):
					obstacle.obstacle_changed.disconnect(_on_obstacle_changed)
		else:
			# Became dynamic - add to dynamic list
			obstacle.pos_threshold = PathfindingConstants.DYNAMIC_POSITION_THRESHOLD
			obstacle.rot_threshold = PathfindingConstants.DYNAMIC_ROTATION_THRESHOLD
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
	
	obstacles_changed.emit()
	print("=== END OBSTACLE CHANGED ===")
