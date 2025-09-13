@tool
extends RefCounted
class_name AStarPathfinding

var system: PathfinderSystem

# Pathfinding components
var open_set: Array[PathNode] = []
var closed_set: Dictionary = {}

var pool: PathNodePool

func _init(pathfinder_system: PathfinderSystem, node_pool: PathNodePool):
	system = pathfinder_system
	pool = node_pool

func cleanup_path_nodes():
	var all_nodes: Array[PathNode] = []
	all_nodes.append_array(open_set)
	
	open_set.clear()
	closed_set.clear()
	
	# Return nodes to pool
	pool.return_nodes(all_nodes)

func a_star_pathfind_circle(start: Vector2, goal: Vector2, agent_full_size: float, mask: int) -> PackedVector2Array:
	open_set.clear()
	closed_set.clear()
	
	# add start node
	open_set.append(pool.get_node(start, 0.0, _heuristic(start, goal)))
	
	var iterations = 0
	var max_iterations = PathfindingConstants.MAX_PATHFINDING_ITERATIONS
	
	# Dynamic goal tolerance based on agent size
	var goal_tolerance = max(system.grid_size * PathfindingConstants.GOAL_TOLERANCE_GRID_SIZE_FACTOR, agent_full_size * PathfindingConstants.GOAL_TOLERANCE_RADIUS_FACTOR)

	print("DEBUG: A* starting - start:", start, " goal:", goal, " tolerance:", goal_tolerance)

	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1
		
		# Find lowest f_score
		var current_idx = 0
		for i in range(1, open_set.size()):
			if open_set[i].f_score < open_set[current_idx].f_score:
				current_idx = i
		
		var current = open_set[current_idx]
		open_set.remove_at(current_idx)
		
		# Check if we reached the goal (with tolerance)
		var snapped_goal = system.grid_manager.snap_to_grid(goal)
		if current.position.distance_to(snapped_goal) < goal_tolerance:
			print("DEBUG: A* found path in ", iterations, " iterations")
			return _reconstruct_path(current)
		
		closed_set[current.position] = true

		# Get neighbors with dynamic step size
		var neighbors = _get_adaptive_neighbors(current.position, agent_full_size)
		
		var valid_neighbors = 0
		var unsafe_neighbors = 0
		var path_blocked_neighbors = 0
		
		for neighbor_pos in neighbors:
			if closed_set.has(neighbor_pos):
				continue
			
			if PathfindingUtils.is_circle_position_unsafe(system, neighbor_pos, agent_full_size, mask):
				unsafe_neighbors += 1
				continue
			
			if not PathfindingUtils.is_safe_circle_path(system, current.position, neighbor_pos, agent_full_size, mask):
				path_blocked_neighbors += 1
				continue
			
			valid_neighbors += 1
			
			var movement_cost = current.position.distance_to(neighbor_pos)
			var tentative_g = current.g_score + movement_cost
			
			var existing_node = null
			for node in open_set:
				if node.position.distance_to(neighbor_pos) < system.grid_size * PathfindingConstants.NODE_DISTANCE_THRESHOLD:  # Close enough
					existing_node = node
					break
			
			if existing_node == null:
				var new_node = pool.get_node(neighbor_pos, tentative_g, _heuristic(neighbor_pos, goal))
				open_set.append(new_node)
				new_node.parent = current
			elif tentative_g < existing_node.g_score:
				existing_node.g_score = tentative_g
				existing_node.f_score = tentative_g + existing_node.h_score
				existing_node.parent = current
		
		if valid_neighbors == 0:
			print("DEBUG: No valid neighbors from ", current.position, " - unsafe:", unsafe_neighbors, " blocked:", path_blocked_neighbors, " total_neighbors:", neighbors.size())
		
		system.array_pool.return_vector2_array(neighbors)
		
	# Debug why A* failed
	if open_set.is_empty():
		print("DEBUG: A* failed - open set exhausted after ", iterations, " iterations")
	else:
		print("DEBUG: A* failed - max iterations reached (", iterations, ")")
	
	# will be returned to pool in agent
	return system.array_pool.get_packedVector2_array()

func _get_adaptive_neighbors(pos: Vector2, agent_full_size: float) -> Array[Vector2]:
	# cleanup will happen in caller func
	var neighbors: Array[Vector2] = system.array_pool.get_vector2_array()
	
	# Use smaller steps for larger agents to find more precise paths
	var step_size = system.grid_size
	if agent_full_size > system.grid_size * PathfindingConstants.LARGE_AGENT_THRESHOLD:
		step_size = max(system.grid_size * PathfindingConstants.MIN_STEP_SIZE_FACTOR, agent_full_size * PathfindingConstants.ADAPTIVE_STEP_FACTOR)  # Adaptive step size
	
	# Standard 8-direction movement
	var directions = [
		Vector2(step_size, 0), Vector2(-step_size, 0),
		Vector2(0, step_size), Vector2(0, -step_size),
		Vector2(step_size, step_size), Vector2(-step_size, -step_size),
		Vector2(step_size, -step_size), Vector2(-step_size, step_size)
	]
	
	# For larger agents, also try half-steps to find tighter passages
	if agent_full_size > system.grid_size * PathfindingConstants.HALF_STEP_THRESHOLD:
		var half_step: float = step_size * PathfindingConstants.MIN_STEP_SIZE_FACTOR
		directions.append_array([
			Vector2(half_step, 0), Vector2(-half_step, 0),
			Vector2(0, half_step), Vector2(0, -half_step)
		])
	
	for direction in directions:
		var neighbor = pos + direction
		
		# Check if within bounds
		if PathfindingUtils.is_point_in_polygon(neighbor, system.bounds_polygon):
			neighbors.append(neighbor)
	
	return neighbors

func _heuristic(pos: Vector2, goal: Vector2) -> float:
	return pos.distance_to(goal)

func _reconstruct_path(end_node: PathNode) -> PackedVector2Array:
	# will be returned to pool in agent
	var path: PackedVector2Array = system.array_pool.get_packedVector2_array()
	var temp_positions: Array[Vector2] = []
	
	var current = end_node
	while current != null:
		temp_positions.append(current.position)
		current = current.parent  # This would need to be added to PathNode
	
	# Build final path in correct order
	path.resize(temp_positions.size())
	for i in temp_positions.size():
		path[i] = temp_positions[temp_positions.size() - 1 - i]
	
	return path
