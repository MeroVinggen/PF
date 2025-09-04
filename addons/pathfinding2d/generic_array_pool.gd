@tool
extends RefCounted
class_name GenericArrayPool

var pool_size: int
var pool_allow_expand: bool
var pool_expand_step: int

# Separate pools for each type
var vector2_pool: Array = []
var int_pool: Array = []
var pathnode_pool: Array = []

# Stats tracking
var vector2_created: int = 0
var int_created: int = 0
var pathnode_created: int = 0
var expansions: int = 0

func _init(initial_size: int, allow_expand: bool = true, expand_step: int = 10):
	pool_size = initial_size
	pool_allow_expand = allow_expand
	pool_expand_step = expand_step
	
	# Pre-populate all pools
	_expand_pool(vector2_pool, pool_size)
	_expand_pool(int_pool, pool_size)
	_expand_pool(pathnode_pool, pool_size)

func get_vector2_array() -> Array[Vector2]:
	var array: Array[Vector2]
	
	if vector2_pool.is_empty():
		if pool_allow_expand:
			_expand_pool(vector2_pool, pool_expand_step)
			expansions += 1
			array = vector2_pool.pop_back()
		else:
			array = []
			vector2_created += 1
	else:
		array = vector2_pool.pop_back()
	
	array.clear()
	return array

func get_int_array() -> Array[int]:
	var array: Array[int]
	
	if int_pool.is_empty():
		if pool_allow_expand:
			_expand_pool(int_pool, pool_expand_step)
			expansions += 1
			array = int_pool.pop_back()
		else:
			array = []
			int_created += 1
	else:
		array = int_pool.pop_back()
	
	array.clear()
	return array

func get_pathnode_array() -> Array[PathNode]:
	var array: Array[PathNode]
	
	if pathnode_pool.is_empty():
		if pool_allow_expand:
			_expand_pool(pathnode_pool, pool_expand_step)
			expansions += 1
			array = pathnode_pool.pop_back()
		else:
			array = []
			pathnode_created += 1
	else:
		array = pathnode_pool.pop_back()
	
	array.clear()
	return array

func return_vector2_array(array: Array[Vector2]) -> void:
	_return_array(array, vector2_pool)

func return_int_array(array: Array[int]) -> void:
	_return_array(array, int_pool)

func return_pathnode_array(array: Array[PathNode]) -> void:
	_return_array(array, pathnode_pool)

func get_pool_stats() -> Dictionary:
	return {
		"pool_size": pool_size,
		"vector2_available": vector2_pool.size(),
		"int_available": int_pool.size(),
		"pathnode_available": pathnode_pool.size(),
		"vector2_created": vector2_created,
		"int_created": int_created,
		"pathnode_created": pathnode_created,
		"total_expansions": expansions
	}

# Private helper methods
func _return_array(array, pool: Array) -> void:
	if array == null:
		return
	array.clear()
	if pool.size() < pool_size:
		pool.append(array)

func _expand_pool(pool: Array, count: int) -> void:
	for i in count:
		pool.append([])
