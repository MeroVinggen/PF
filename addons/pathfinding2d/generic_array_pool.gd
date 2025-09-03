@tool
extends RefCounted
class_name GenericArrayPool

var pool_name: String
var pool_size: int
var pool_allow_expand: bool
var pool_expand_step: int

var available_arrays: Array[Array] = []
var total_created: int = 0
var total_expansions: int = 0

func _init(name: String, initial_size: int, allow_expand: bool = true, expand_step: int = 10):
	pool_name = name
	pool_size = initial_size
	pool_allow_expand = allow_expand
	pool_expand_step = expand_step
	
	# Pre-populate the pool
	_expand_pool(pool_size)

func get_array() -> Array:
	var array: Array
	
	if available_arrays.is_empty():
		# Pool is empty
		if pool_allow_expand:
			_expand_pool(pool_expand_step)
			total_expansions += 1
			array = available_arrays.pop_back()
		else:
			# Create new instance without pooling
			array = []
			total_created += 1
	else:
		array = available_arrays.pop_back()
	
	# Array should already be clear, but ensure it
	array.clear()
	return array

func return_array(array: Array) -> void:
	if array == null:
		return
	
	# Clear the array
	array.clear()
	
	# Only return to pool if we haven't exceeded our limits
	if available_arrays.size() < pool_size:
		available_arrays.append(array)

func return_arrays(arrays: Array[Array]) -> void:
	for array in arrays:
		return_array(array)

func get_pool_stats() -> Dictionary:
	return {
		"pool_name": pool_name,
		"pool_size": pool_size,
		"available": available_arrays.size(),
		"in_use": pool_size - available_arrays.size(),
		"total_created": total_created,
		"total_expansions": total_expansions,
		"allow_expand": pool_allow_expand,
		"expand_step": pool_expand_step
	}

func _expand_pool(count: int) -> void:
	for i in count:
		var array = []
		available_arrays.append(array)
		total_created += 1
	
	# Update pool size to reflect expansion
	if pool_allow_expand:
		pool_size += count
