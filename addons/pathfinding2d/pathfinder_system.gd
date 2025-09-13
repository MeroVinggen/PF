@tool
extends Node2D
class_name PathfinderSystem

@export var bounds_polygon: PackedVector2Array = PackedVector2Array([
	Vector2.ZERO,
	Vector2(500, 0),
	Vector2(500, 500),
	Vector2(0, 500)
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

func init():
	path_node_pool = PathNodePool.new(pool_size, pool_allow_expand, pool_expand_step)
	array_pool = GenericArrayPool.new(array_pool_size, array_pool_allow_expand, array_pool_expand_step)
	
	grid_manager = GridManager.new(self)
	obstacle_manager = ObstacleManager.new(self)
	astar_pathfinding = AStarPathfinding.new(self, path_node_pool)
	batch_manager = BatchUpdateManager.new(self, batch_update_fps)
	spatial_partition = SpatialPartition.new(self, grid_size * sector_size_multiplier, quadtree_max_objects, quadtree_max_levels)
	request_queue = PathfindingRequestQueue.new(self, 3, 5.0)
	
	_initialize_system()
	set_physics_process(true)

# prevent errs in the editor mode
func _ready() -> void:
	set_physics_process(false)

func _physics_process(delta: float) -> void:
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
		obstacle.update_data()
		var bounds = PathfindingUtils.get_polygon_bounds(obstacle.cached_world_polygon)
		print("Obstacle ", i, ": pos=", obstacle.global_position, " bounds=", bounds, " static=", obstacle.is_static)
		obstacle_manager.register_initial_obstacle(obstacle)
	print("=== END INITIAL OBSTACLES ===")

#func _invalidate_affected_paths():
	#for pathfinder in pathfinders:
		#if pathfinder.is_moving and not PathfindingUtils.is_path_safe(pathfinder.system, pathfinder.current_path, pathfinder.global_position, pathfinder.path_index, pathfinder.agent_full_size, pathfinder.mask):
			#pathfinder._recalculate_or_find_alternative()

func register_pathfinder(pathfinder: PathfinderAgent):
	if pathfinder not in pathfinders:
		pathfinders.append(pathfinder)
	
	_prepare_registered_pathfinder(pathfinder)

func _prepare_registered_pathfinder(pathfinder: PathfinderAgent):
	pathfinder.register(self)
	spatial_partition.add_agent(pathfinder)

func unregister_pathfinder(pathfinder: PathfinderAgent):
	pathfinders.erase(pathfinder)
	pathfinder.unregister()
	spatial_partition.remove_agent(pathfinder)
