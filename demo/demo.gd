# Enhanced demo script showcasing dynamic pathfinding features
extends Node2D

@onready var pathfinder_system = $PathfinderSystem
@onready var pathfinder = $Pathfinder
@onready var dynamic_obstacle = $PathfinderObstacleD
@onready var static_obstacle = $PathfinderObstacleS

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

func _physics_process(_delta: float) -> void:
	_update_debug_ui()

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
	print("=== MOVING DYNAMIC OBSTACLE ===")
	print("From: ", dynamic_obstacle.global_position, " To: ", target)
	
	if dynamic_obstacle:
		# Create a smooth movement tween
		var tween = create_tween()
		tween.tween_property(dynamic_obstacle, "global_position", target, 1.0)
		tween.tween_callback(_on_obstacle_movement_complete.bind(target))
	else:
		print("ERROR: No dynamic obstacle available")

func _on_obstacle_movement_complete(target_pos: Vector2):
	print("=== OBSTACLE MOVEMENT COMPLETE ===")
	print("Dynamic obstacle now at: ", dynamic_obstacle.global_position)
	print("Target was: ", target_pos)
	print("Distance from target: ", dynamic_obstacle.global_position.distance_to(target_pos))
	
	# Force a grid update after movement
	if pathfinder_system:
		print("Forcing grid update after obstacle movement")
		pathfinder_system.force_grid_update()

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
