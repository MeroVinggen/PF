@tool
extends RefCounted
class_name BatchUpdateManager

signal batch_processed()

var system: PathfinderSystem
var pending_updates: Dictionary = {}
var frame_timer: float = 0.0
var update_interval: float

var changed_obstacles: Array[PathfinderObstacle] = []

func _init(pathfinder_system: PathfinderSystem, update_fps: int):
	system = pathfinder_system
	update_interval = 1.0 / update_fps

func queue_obstacle_update(obstacle: PathfinderObstacle, update_type: String):
	if obstacle not in changed_obstacles:
		changed_obstacles.append(obstacle)
		
	if not pending_updates.has(obstacle):
		pending_updates[obstacle] = {}
	
	pending_updates[obstacle][update_type] = true

func queue_grid_update():
	pending_updates["grid_update"] = true

func queue_path_recalculation():
	pending_updates["path_recalc"] = true

func process_frame(delta: float):
	frame_timer += delta
	if frame_timer >= update_interval:
		frame_timer = 0.0
		_process_batch()

func _process_batch():
	if pending_updates.is_empty():
		return
	
	var grid_needs_update = false
	var paths_need_recalc = false
	var obstacles_to_update: Array[PathfinderObstacle] = []
	
	# Process obstacle updates
	for item in pending_updates:
		if item is PathfinderObstacle:
			var obstacle = item as PathfinderObstacle
			var updates = pending_updates[item]
			
			if updates.has("static_changed"):
				_process_static_change(obstacle)
				grid_needs_update = true
			
			if updates.has("position_changed"):
				obstacles_to_update.append(obstacle)
				grid_needs_update = true
				paths_need_recalc = true
		
		elif item == "grid_update":
			grid_needs_update = true
		elif item == "path_recalc":
			paths_need_recalc = true
	
	for obstacle in obstacles_to_update:
		system.spatial_partition.update_obstacle(obstacle)
	
	# Batch execute updates
	if grid_needs_update:
		system.grid_manager.update_grid_for_dynamic_obstacles()
	
	if paths_need_recalc:
		_recalculate_invalid_paths()
	
	changed_obstacles.clear()
	pending_updates.clear()
	batch_processed.emit()

func _process_static_change(obstacle: PathfinderObstacle):
	if obstacle.is_static:
		system.obstacle_manager.dynamic_obstacles.erase(obstacle)
		obstacle.pos_threshold = PathfindingConstants.STATIC_POSITION_THRESHOLD
		obstacle.rot_threshold = PathfindingConstants.STATIC_ROTATION_THRESHOLD
	else:
		if obstacle not in system.obstacle_manager.dynamic_obstacles:
			system.obstacle_manager.dynamic_obstacles.append(obstacle)
		obstacle.pos_threshold = PathfindingConstants.DYNAMIC_POSITION_THRESHOLD
		obstacle.rot_threshold = PathfindingConstants.DYNAMIC_ROTATION_THRESHOLD

func _recalculate_invalid_paths():
	var nearby_agents: Array[PathfinderAgent] = []
	
	# For each changed obstacle, find nearby agents using spatial partition
	for obstacle in changed_obstacles:
		nearby_agents.append_array(system.spatial_partition.get_agents_near_obstacle(obstacle))
	
	# Trigger recalculation for all affected agents
	for agent in nearby_agents:
		agent._recalculate_or_find_alternative()
