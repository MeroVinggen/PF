@tool
extends RefCounted
class_name GenericArrayPool

var pool_size: int
var pool_allow_expand: bool
var pool_expand_step: int

var vector2_pool: Array = []
var vector2i_pool: Array = []
var packedVector2_pool: Array = []
var obstacles_pool: Array = []
var request_pool: Array = []

func _init(initial_size: int, allow_expand: bool = true, expand_step: int = 10):
	pool_size = initial_size
	pool_allow_expand = allow_expand
	pool_expand_step = expand_step
	
	# Pre-populate all pools
	_expand_pool(&"vector2_pool", vector2_pool, pool_size)
	_expand_pool(&"vector2i_pool", vector2i_pool, pool_size)
	_expand_pool(&"packedVector2_pool", packedVector2_pool, pool_size)
	_expand_pool(&"obstacles_pool", obstacles_pool, pool_size)
	_expand_pool(&"request_pool", request_pool, pool_size)

func get_vector2_array() -> Array[Vector2]:
	var array: Array[Vector2]
	
	if vector2_pool.is_empty():
		if pool_allow_expand:
			_expand_pool(&"vector2_pool", vector2_pool, pool_expand_step)
			array = vector2_pool.pop_back() as Array[Vector2]
		else:
			array = []
	else:
		array = vector2_pool.pop_back() as Array[Vector2]
	
	array.clear()
	return array

func get_vector2i_array() -> Array[Vector2i]:
	var array: Array[Vector2i]
	
	if vector2i_pool.is_empty():
		if pool_allow_expand:
			_expand_pool(&"vector2i_pool", vector2i_pool, pool_expand_step)
			array = vector2i_pool.pop_back() as Array[Vector2i]
		else:
			array = []
	else:
		array = vector2i_pool.pop_back() as Array[Vector2i]
	
	array.clear()
	return array

func get_packedVector2_array() -> PackedVector2Array:
	var array: PackedVector2Array
	
	if packedVector2_pool.is_empty():
		if pool_allow_expand:
			_expand_pool(&"packedVector2_pool", packedVector2_pool, pool_expand_step)
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
			_expand_pool(&"obstacles_pool", obstacles_pool, pool_expand_step)
			array = obstacles_pool.pop_back() as Array[PathfinderObstacle]
		else:
			array = []
	else:
		array = obstacles_pool.pop_back() as Array[PathfinderObstacle]
	
	array.clear()
	return array

func get_pathfinding_request() -> PathfindingRequest:
	if request_pool.is_empty():
		return PathfindingRequest.new()
	return request_pool.pop_back()

func return_vector2_array(array: Array[Vector2]) -> void:
	_return_array(array, vector2_pool)

func return_vector2i_array(array: Array[Vector2i]) -> void:
	_return_array(array, vector2i_pool)

func return_packedVector2_array(array: PackedVector2Array) -> void:
	_return_array(array, packedVector2_pool)

func return_obstacles_array(array: Array[PathfinderObstacle]) -> void:
	_return_array(array, obstacles_pool)

func return_pathfinding_request(request: PathfindingRequest):
	request.agent = null
	request_pool.append(request)

func _return_array(array, pool: Array) -> void:
	array.clear()
	if pool.size() < pool_size:
		pool.append(array)

func _expand_pool(pool_name: StringName, pool: Array, count: int) -> void:
	for i in count:
		if pool_name == "vector2_pool":
			var typed_array: Array[Vector2] = []
			pool.append(typed_array)
		elif pool_name == "packedVector2_pool":
			var typed_array: PackedVector2Array = []
			pool.append(typed_array)
		elif pool_name == "vector2i_pool":
			var typed_array: Array[Vector2i] = []
			pool.append(typed_array)
		elif pool_name == "obstacles_pool":
			var typed_array: Array[PathfinderObstacle] = []
			pool.append(typed_array)
		elif pool_name == "request_pool":
			var typed_array: Array[PathfindingRequest] = []
			pool.append(PathfindingRequest.new())
		else:
			# Fallback for unknown pool types
			pool.append([])
