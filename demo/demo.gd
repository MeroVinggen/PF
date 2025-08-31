# Enhanced demo script showcasing dynamic pathfinding features
extends Node2D

@onready var pathfinder_system = $PathfinderSystem
@onready var pathfinder = $Pathfinder
@onready var dynamic_obstacle = $PathfinderObstacleD
@onready var static_obstacle = $PathfinderObstacleS

# Demo control variables
var obstacle_move_speed: float = 50.0
var obstacle_direction: Vector2 = Vector2.RIGHT

func _ready():
	print("=== Enhanced Pathfinding Demo Starting ===")
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	_setup_pathfinder_signals()
	_setup_demo_ui()
	
	print("=== Demo Ready ===")
	print("Controls:")
	print("  Left Click - Move to position")
	print("  Right Click - Move dynamic obstacle")
	print("  R - Force grid update")

func _setup_pathfinder_signals():
	if pathfinder:
		pathfinder.path_found.connect(_on_path_found)
		pathfinder.destination_reached.connect(_on_destination_reached)
		pathfinder.path_blocked.connect(_on_path_blocked)
		pathfinder.agent_stuck.connect(_on_agent_stuck)
		pathfinder.agent_unstuck.connect(_on_agent_unstuck)
		pathfinder.path_invalidated.connect(_on_path_invalidated)
		pathfinder.path_recalculated.connect(_on_path_recalculated)
		print("All pathfinder signals connected")

func _setup_demo_ui():
	# Create UI labels for debug info
	var label = Label.new()
	label.position = Vector2(10, 10)
	label.add_theme_color_override("font_color", Color.WHITE)
	add_child(label)
	label.name = "DebugLabel"

func _process(delta):
	_update_debug_ui()

func _demo_oscillating_obstacle(delta):
	"""Move dynamic obstacle back and forth"""
	if not dynamic_obstacle:
		return
	
	var movement = obstacle_direction * obstacle_move_speed * delta
	dynamic_obstacle.global_position += movement
	
	# Reverse direction at boundaries
	if dynamic_obstacle.global_position.x > 600 or dynamic_obstacle.global_position.x < 100:
		obstacle_direction.x *= -1
	
	if dynamic_obstacle.global_position.y > 500 or dynamic_obstacle.global_position.y < 100:
		obstacle_direction.y *= -1

# UPDATED: Simplified debug UI function
func _update_debug_ui():
	var label = get_node_or_null("DebugLabel") as Label
	if not label:
		return
	
	var info = []
	
	if pathfinder_system:
		info.append("Grid: " + str(pathfinder_system.grid.size()))
		info.append("Dynamic: " + str(pathfinder_system.get_dynamic_obstacle_count()))
		info.append("Dirty: " + str(pathfinder_system.is_grid_dirty()))
	
	if pathfinder:
		info.append("Moving: " + str(pathfinder.is_moving))
		info.append("Valid: " + str(pathfinder.is_path_valid()))
		info.append("Failures: " + str(pathfinder.consecutive_failed_recalcs))
		info.append("Stuck: " + str(pathfinder.is_stuck()))
	
	info.append("\nLClick=Move, RClick=MoveObstacle, R=Update")
	label.text = "\n".join(info)

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var target = get_global_mouse_position()
			_test_pathfinding_to(target)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var target = get_global_mouse_position()
			_move_dynamic_obstacle_to(target)
	
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				_force_grid_update()

func _test_pathfinding_to(target: Vector2):
	print("Moving agent to: ", target)
	
	if pathfinder:
		pathfinder.move_to(target)
	else:
		print("ERROR: No pathfinder available")

func _move_dynamic_obstacle_to(target: Vector2):
	print("Moving dynamic obstacle to: ", target)
	
	if dynamic_obstacle:
		# Create a smooth movement tween
		var tween = create_tween()
		tween.tween_property(dynamic_obstacle, "global_position", target, 1.0)
		tween.tween_callback(_on_obstacle_movement_complete)
	else:
		print("ERROR: No dynamic obstacle available")

func _on_obstacle_movement_complete():
	print("Dynamic obstacle movement completed")

func _force_grid_update():
	if pathfinder_system:
		pathfinder_system.force_grid_update()
		print("Forced grid update")
	else:
		print("No pathfinder system available")

# Signal handlers
func _on_path_found(path: PackedVector2Array):
	print("✓ Path found with ", path.size(), " waypoints")

func _on_destination_reached():
	print("✓ Destination reached!")

func _on_path_blocked():
	print("✗ Path blocked - no route available!")

func _on_agent_stuck():
	print("⚠ Agent is stuck! Recovery initiated...")

func _on_agent_unstuck():
	print("✓ Agent successfully unstuck!")

func _on_path_invalidated():
	print("⚠ Path became invalid due to dynamic obstacles")

func _on_path_recalculated():
	print("✓ Path successfully recalculated")

# UPDATED: Simplified stress test function
func _start_stress_test():
	"""Start a stress test with multiple moving obstacles"""
	print("Starting pathfinding stress test...")
	
	# Create multiple dynamic obstacles
	for i in range(3):
		var new_obstacle = preload("res://addons/pathfinding2d/pathfinder_obstacle.gd").new()
		new_obstacle.is_static = false
		new_obstacle.obstacle_polygon = PackedVector2Array([
			Vector2(-15, -15), Vector2(15, -15), 
			Vector2(15, 15), Vector2(-15, 15)
		])
		new_obstacle.global_position = Vector2(200 + i * 100, 200 + i * 50)
		add_child(new_obstacle)
		
		# Make them move in different patterns
		var tween = create_tween()
		tween.set_loops()
		var target1 = Vector2(100 + i * 150, 150)
		var target2 = Vector2(500 - i * 100, 400)
		tween.tween_property(new_obstacle, "global_position", target1, 2.0 + i * 0.5)
		tween.tween_property(new_obstacle, "global_position", target2, 2.0 + i * 0.5)
	
	# Start pathfinder moving in a complex pattern
	if pathfinder:
		_complex_movement_pattern()

func _complex_movement_pattern():
	"""Make pathfinder follow a complex movement pattern"""
	var targets = [
		Vector2(100, 100), Vector2(600, 100),
		Vector2(600, 500), Vector2(100, 500),
		Vector2(350, 300)
	]
	
	_move_through_targets(targets, 0)

func _move_through_targets(targets: Array, index: int):
	"""Recursively move through a series of targets"""
	if index >= targets.size():
		index = 0  # Loop back to start
	
	pathfinder.move_to(targets[index])
	
	# Wait for destination to be reached, then move to next target
	await pathfinder.destination_reached
	await get_tree().create_timer(1.0).timeout  # Brief pause
	
	_move_through_targets(targets, index + 1)

func _draw():
	"""Draw additional debug information"""
	if not pathfinder_system:
		return
	
	# Draw system bounds
	if pathfinder_system.bounds_polygon.size() >= 3:
		var points = pathfinder_system.bounds_polygon
		for i in range(points.size()):
			var start = points[i]
			var end = points[(i + 1) % points.size()]
			draw_line(start, end, Color.BLUE, 2.0)
	
	# Draw grid points (sampling for performance)
	if pathfinder_system.grid.size() > 0:
		var sample_rate = max(1, pathfinder_system.grid.size() / 500)  # Limit to ~500 points
		var i = 0
		for pos in pathfinder_system.grid.keys():
			if i % sample_rate == 0:
				var color = Color.GREEN if pathfinder_system.grid[pos] else Color.RED
				draw_circle(pos, 2.0, color * 0.3)
			i += 1
	
	# UPDATED: Simplified dynamic obstacle visualization
	for obstacle in pathfinder_system.dynamic_obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var world_poly = obstacle.get_world_polygon()
		if world_poly.size() >= 3:
			# Draw simple influence circle instead of complex polygon expansion
			var center = _get_polygon_center(world_poly)
			var radius = _get_polygon_max_radius(world_poly, center)
			draw_arc(center, radius + pathfinder_system.agent_buffer, 0, TAU, 32, Color.ORANGE * 0.5, 2.0)

# UPDATED: Simplified helper functions
func _get_polygon_center(polygon: PackedVector2Array) -> Vector2:
	"""Calculate the center point of a polygon"""
	if polygon.is_empty():
		return Vector2.ZERO
	
	var sum = Vector2.ZERO
	for point in polygon:
		sum += point
	
	return sum / polygon.size()

func _get_polygon_max_radius(polygon: PackedVector2Array, center: Vector2) -> float:
	"""Get maximum distance from center to any polygon vertex"""
	var max_radius = 0.0
	
	for point in polygon:
		var distance = center.distance_to(point)
		max_radius = max(max_radius, distance)
	
	return max_radius
