@tool
extends RefCounted
class_name GenericArrayPool

var pool_size: int
var pool_allow_expand: bool
var pool_expand_step: int

var vector2_pool: Array = []
var packedVector2_pool: Array = []
var pathfinder_pool: Array = []
var obstacles_pool: Array = []


func _init(initial_size: int, allow_expand: bool = true, expand_step: int = 10):
	pool_size = initial_size
	pool_allow_expand = allow_expand
	pool_expand_step = expand_step
	
	# Pre-populate all pools
	_expand_pool(vector2_pool, pool_size)
	_expand_pool(packedVector2_pool, pool_size)
	_expand_pool(pathfinder_pool, pool_size)
	_expand_pool(obstacles_pool, pool_size)

func get_vector2_array() -> Array[Vector2]:
	var array: Array[Vector2]
	
	if vector2_pool.is_empty():
		if pool_allow_expand:
			_expand_pool(vector2_pool, pool_expand_step)
			array = vector2_pool.pop_back() as Array[Vector2]
		else:
			array = []
	else:
		array = vector2_pool.pop_back() as Array[Vector2]
	
	array.clear()
	return array

func get_pathfinder_array() -> Array[PathfinderAgent]:
	var array: Array[PathfinderAgent]
	if pathfinder_pool.is_empty():
		if pool_allow_expand:
			_expand_pool(pathfinder_pool, pool_expand_step)
			array = pathfinder_pool.pop_back() as Array[PathfinderAgent]
		else:
			array = []
	else:
		array = pathfinder_pool.pop_back() as Array[PathfinderAgent]
	array.clear()
	return array

func get_packedVector2_array() -> PackedVector2Array:
	var array: PackedVector2Array
	
	if packedVector2_pool.is_empty():
		if pool_allow_expand:
			_expand_pool(packedVector2_pool, pool_expand_step)
			array = packedVector2_pool.pop_back() as PackedVector2Array
		else:
			array = []
	else:
		array = packedVector2_pool.pop_back() as PackedVector2Array
	
	array.clear()
	return array

func get_obstacle_array() -> Array[PathfinderObstacle]:
	var array: Array[PathfinderObstacle]
	
	if obstacles_pool.is_empty():
		if pool_allow_expand:
			_expand_pool(obstacles_pool, pool_expand_step)
			array = obstacles_pool.pop_back() as Array[PathfinderObstacle]
		else:
			array = []
	else:
		array = obstacles_pool.pop_back() as Array[PathfinderObstacle]
	
	array.clear()
	return array

func return_vector2_array(array: Array[Vector2]) -> void:
	_return_array(array, vector2_pool)

func return_pathfinder_array(array: Array[PathfinderAgent]) -> void:
	_return_array(array, pathfinder_pool)

func return_packedVector2_array(array: PackedVector2Array) -> void:
	_return_array(array, packedVector2_pool)

func return_obstacles_array(array: Array[PathfinderObstacle]) -> void:
	_return_array(array, obstacles_pool)

func _return_array(array, pool: Array) -> void:
	if array == null:
		return
	array.clear()
	if pool.size() < pool_size:
		pool.append(array)

func _expand_pool(pool: Array, count: int) -> void:
	for i in count:
		if pool == vector2_pool:
			var typed_array: Array[Vector2] = []
			pool.append(typed_array)
		elif pool == pathfinder_pool:
			var typed_array: Array[PathfinderAgent] = []
			pool.append(typed_array)
		elif pool == packedVector2_pool:
			var typed_array: PackedVector2Array = []
			pool.append(typed_array)
		elif pool == obstacles_pool:
			var typed_array: Array[PathfinderObstacle] = []
			pool.append(typed_array)
		else:
			# Fallback for unknown pool types
			pool.append([])
