@tool
extends RefCounted
class_name PathNodePool

var pool_size: int
var pool_allow_expand: bool
var pool_expand_step: int

var available_nodes: Array[PathNode] = []
var total_created: int = 0
var total_expansions: int = 0

func _init(initial_size: int, allow_expand: bool = true, expand_step: int = 10):
	pool_size = initial_size
	pool_allow_expand = allow_expand
	pool_expand_step = expand_step
	
	# Pre-populate the pool
	_expand_pool(pool_size)

func get_node(pos: Vector2 = Vector2.ZERO, g: float = 0.0, h: float = 0.0) -> PathNode:
	var node: PathNode
	
	if available_nodes.is_empty():
		# Pool is empty
		if pool_allow_expand:
			_expand_pool(pool_expand_step)
			total_expansions += 1
			node = available_nodes.pop_back()
		else:
			# Create new instance without pooling
			node = PathNode.new()
			total_created += 1
	else:
		node = available_nodes.pop_back()
	
	# Initialize/reset the node
	node.position = pos
	node.g_score = g
	node.h_score = h
	node.f_score = g + h
	
	return node

func return_node(node: PathNode) -> void:
	if node == null:
		return
	
	# Reset node state
	node.position = Vector2.ZERO
	node.g_score = 0.0
	node.h_score = 0.0
	node.f_score = 0.0
	
	# Only return to pool if we haven't exceeded our limits
	if available_nodes.size() < pool_size:
		available_nodes.append(node)

func return_nodes(nodes: Array[PathNode]) -> void:
	for node in nodes:
		return_node(node)

func _expand_pool(count: int) -> void:
	for i in count:
		var node = PathNode.new()
		available_nodes.append(node)
		total_created += 1
	
	# Update pool size to reflect expansion
	if pool_allow_expand:
		pool_size += count
