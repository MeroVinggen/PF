@tool
extends RefCounted
class_name ObstacleManager

signal obstacles_changed()

var system: PathfinderSystem
var dynamic_obstacles: Array[PathfinderObstacle] = []

func _init(pathfinder_system: PathfinderSystem):
	system = pathfinder_system

func register_obstacle(obstacle: PathfinderObstacle):
	if obstacle in system.obstacles:
		return
	
	system.obstacles.append(obstacle)
	system.spatial_partition.add_obstacle(obstacle)
	_prepare_registered_obstacle(obstacle)

func register_initial_obstacle(obstacle) -> void:
	system.spatial_partition.add_obstacle(obstacle)
	_prepare_registered_obstacle(obstacle)

func unregister_obstacle(obstacle: PathfinderObstacle):
	system.obstacles.erase(obstacle)
	system.spatial_partition.remove_obstacle(obstacle)
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

func _on_obstacle_static_changed(obstacle: PathfinderObstacle):
	system.batch_manager.queue_obstacle_update(obstacle, "static_changed")

func _on_obstacle_changed(obstacle: PathfinderObstacle):
	system.spatial_partition.update_obstacle(obstacle)
	system.batch_manager.queue_obstacle_update(obstacle, "position_changed")
	system.batch_manager.queue_path_recalculation()
