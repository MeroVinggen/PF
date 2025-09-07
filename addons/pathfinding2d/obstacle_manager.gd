@tool
extends RefCounted
class_name ObstacleManager

signal obstacles_changed()

var system: PathfinderSystem
var pending_static_changes: Array[PathfinderObstacle] = []
var dynamic_obstacles: Array[PathfinderObstacle] = []

func _init(pathfinder_system: PathfinderSystem):
	system = pathfinder_system

func update_system():
	if not pending_static_changes.is_empty():
		_process_batched_static_changes()

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

func _prepare_registered_obstacle(obstacle: PathfinderObstacle):
	obstacle.system = system
	
	if not obstacle.is_static and not obstacle.disabled:
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
		obstacle.static_state_changed.connect(_on_obstacle_static_changed)


func _process_batched_static_changes():
	"""Process multiple static/dynamic state changes in one batch"""
	print("Processing ", pending_static_changes.size(), " batched static changes")
	
	var became_static = 0
	var became_dynamic = 0
	
	for obstacle in pending_static_changes:
		if not is_instance_valid(obstacle):
			continue
		
		if obstacle.disabled and obstacle in dynamic_obstacles:
			dynamic_obstacles.erase(obstacle)
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

func _on_obstacle_static_changed(obstacle: PathfinderObstacle):
	# Queue static/dynamic state changes for batch processing
	if obstacle not in pending_static_changes:
		pending_static_changes.append(obstacle)
	
	# For immediate critical cases, still process right away
	if pending_static_changes.size() > PathfindingConstants.MAX_BATCH_SIZE:  # Prevent queue from getting too large
		_process_batched_static_changes()

func _on_obstacle_changed():
	print("DEBUG: OBSTACLE CHANGED EVENT")
	
	# Immediate path invalidation - don't defer this
	for pathfinder in system.pathfinders:
		if pathfinder.is_moving and not pathfinder.is_path_valid():
			pathfinder.recalculate_path()
	
	# Defer only the grid update (less critical)
	if not system.pending_grid_update:
		system.pending_grid_update = true
		system.call_deferred("_process_batched_updates")
	
	update_system()
