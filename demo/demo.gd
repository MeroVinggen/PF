# Enhanced demo script for testing corner avoidance and stuck prevention
extends Node2D

@onready var pathfinder_system = $PathfinderSystem
@onready var pathfinder = $Pathfinder
@onready var obstacles = [$PathfinderObstacle, $PathfinderObstacle2]

var test_points: Array[Vector2] = []
var current_test_index: int = 0
var auto_test_timer: float = 0.0
var auto_test_interval: float = 5.0
var auto_test_enabled: bool = false

func _ready():
	print("=== Enhanced Pathfinding Demo Starting ===")
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	_setup_pathfinder_signals()
	_setup_test_points()
	_debug_system_state()
	
	print("=== Demo Ready ===")
	print("Controls:")
	print("  Left Click - Move to position")
	print("  SPACE - Test problematic corners")
	print("  T - Start/stop automatic testing")
	print("  R - Reset agent position")
	print("  D - Debug system info")

func _setup_pathfinder_signals():
	if pathfinder:
		pathfinder.path_found.connect(_on_path_found)
		pathfinder.destination_reached.connect(_on_destination_reached)
		pathfinder.path_blocked.connect(_on_path_blocked)
		pathfinder.agent_stuck.connect(_on_agent_stuck)
		pathfinder.agent_unstuck.connect(_on_agent_unstuck)
		print("All pathfinder signals connected")

func _setup_test_points():
	# Create test points that are likely to cause corner problems
	if obstacles.size() >= 2:
		var obs1_pos = obstacles[0].global_position
		var obs2_pos = obstacles[1].global_position
		
		# Points near obstacle corners
		test_points.append(obs1_pos + Vector2(30, 30))   # Near corner
		test_points.append(obs1_pos + Vector2(-30, 30))  # Other corner
		test_points.append(obs2_pos + Vector2(35, 35))   # Near second obstacle
		test_points.append(Vector2(100, 600))            # Far point
		test_points.append(Vector2(600, 100))            # Another far point
	else:
		# Default test points if obstacles aren't found
		test_points = [
			Vector2(400, 400),
			Vector2(200, 500),
			Vector2(500, 200),
			Vector2(100, 100),
			Vector2(600, 600)
		]

func _process(delta):
	if auto_test_enabled:
		auto_test_timer += delta
		if auto_test_timer >= auto_test_interval:
			_run_next_test()
			auto_test_timer = 0.0

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var target = get_global_mouse_position()
		_test_pathfinding_to(target, "Mouse Click")
	
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				_test_corner_scenarios()
			KEY_T:
				_toggle_auto_test()
			KEY_R:
				_reset_agent_position()
			KEY_D:
				_debug_system_state()
			KEY_1:
				_set_pathfinder_speed(50.0)
			KEY_2:
				_set_pathfinder_speed(200.0)
			KEY_3:
				_set_pathfinder_speed(400.0)

func _test_pathfinding_to(target: Vector2, test_name: String = "Test"):
	print("\n=== ", test_name, " ===")
	print("Target: ", target)
	print("Agent position: ", pathfinder.global_position if pathfinder else "N/A")
	
	# Check if target is near corners
	if pathfinder_system:
		var near_corner = pathfinder_system._is_near_corner(target, pathfinder.agent_polygon if pathfinder else PackedVector2Array())
		print("Target near corner: ", near_corner)
	
	if pathfinder:
		pathfinder.move_to(target)
	else:
		print("ERROR: No pathfinder available")

func _test_corner_scenarios():
	print("\n=== Corner Scenario Testing ===")
	
	if test_points.is_empty():
		print("No test points available")
		return
	
	var target = test_points[current_test_index % test_points.size()]
	current_test_index += 1
	
	_test_pathfinding_to(target, "Corner Test " + str(current_test_index))

func _toggle_auto_test():
	auto_test_enabled = !auto_test_enabled
	print("Auto-testing ", "enabled" if auto_test_enabled else "disabled")
	
	if auto_test_enabled:
		auto_test_timer = 0.0

func _run_next_test():
	if not pathfinder or pathfinder.is_moving:
		return  # Wait for current movement to complete
	
	_test_corner_scenarios()

func _reset_agent_position():
	if pathfinder:
		pathfinder.stop_movement()
		pathfinder.global_position = Vector2(100, 100)  # Safe starting position
		print("Agent position reset")

func _set_pathfinder_speed(speed: float):
	if pathfinder:
		pathfinder.movement_speed = speed
		print("Agent speed set to: ", speed)

func _debug_system_state():
	print("\n--- Enhanced System Debug ---")
	
	if pathfinder_system:
		print("PathfinderSystem:")
		print("  Position: ", pathfinder_system.global_position)
		print("  Grid size: ", pathfinder_system.grid_size)
		print("  Agent buffer: ", pathfinder_system.agent_buffer)
		print("  Corner buffer: ", pathfinder_system.corner_buffer)
		print("  Grid points: ", pathfinder_system.grid.size())
		print("  Obstacles: ", pathfinder_system.obstacles.size())
	
	if pathfinder:
		print("Pathfinder:")
		print("  Position: ", pathfinder.global_position)
		print("  Is moving: ", pathfinder.is_moving)
		print("  Is stuck: ", pathfinder.is_stuck() if pathfinder.has_method("is_stuck") else "N/A")
		print("  Stuck progress: ", pathfinder.get_stuck_progress() if pathfinder.has_method("get_stuck_progress") else "N/A")
		print("  Movement speed: ", pathfinder.movement_speed)
		print("  Path valid: ", pathfinder.is_path_valid())
	
	# Debug obstacle corner detection
	if pathfinder_system and pathfinder_system.has_method("_find_obstacle_corners"):
		print("Obstacle corners:")
		for i in range(pathfinder_system.obstacles.size()):
			var obstacle = pathfinder_system.obstacles[i]
			if is_instance_valid(obstacle):
				var world_poly = obstacle.get_world_polygon()
				var corners = pathfinder_system._find_obstacle_corners(world_poly)
				print("  Obstacle ", i, ": ", corners.size(), " corners at ", corners)
	
	print("--- End Debug ---\n")

# Signal handlers
func _on_path_found(path: PackedVector2Array):
	print("✓ Path found with ", path.size(), " waypoints")
	if path.size() <= 5:  # Only print if path is short enough
		print("  Path: ", path)

func _on_destination_reached():
	print("✓ Destination reached!")
	
	# If auto-testing and agent reached destination, continue with next test
	if auto_test_enabled:
		auto_test_timer = auto_test_interval - 1.0  # Trigger next test soon

func _on_path_blocked():
	print("✗ Path blocked - no route available!")

func _on_agent_stuck():
	print("⚠ Agent is stuck! Recovery initiated...")

func _on_agent_unstuck():
	print("✓ Agent successfully unstuck!")

# Enhanced debug drawing
func _draw():
	# Draw test points
	for i in range(test_points.size()):
		var point = test_points[i]
		var color = Color.CYAN
		if i == (current_test_index - 1) % test_points.size():
			color = Color.YELLOW  # Highlight last target
		draw_circle(to_local(point), 8, color * 0.5)
		draw_circle(to_local(point), 8, color, false, 2.0)
		
		# Draw number
		var font = ThemeDB.fallback_font
		var text = str(i + 1)
		draw_string(font, to_local(point) + Vector2(-5, -10), text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, color)
	
	# Draw mouse position
	var mouse_pos = get_global_mouse_position()
	draw_circle(to_local(mouse_pos), 5, Color.WHITE * 0.7)
	
	# Draw status info
	var status_pos = Vector2(10, 30)
	var font = ThemeDB.fallback_font
	var status_text = []
	
	if pathfinder:
		if pathfinder.is_moving:
			status_text.append("Status: Moving")
		else:
			status_text.append("Status: Idle")
		
		if pathfinder.has_method("is_stuck") and pathfinder.is_stuck():
			status_text.append("State: STUCK")
		elif pathfinder.has_method("get_stuck_progress"):
			var progress = pathfinder.get_stuck_progress()
			if progress > 0.1:
				status_text.append("Stuck Progress: " + str(int(progress * 100)) + "%")
	
	if auto_test_enabled:
		var time_to_next = auto_test_interval - auto_test_timer
		status_text.append("Next test in: " + str(int(time_to_next)) + "s")
	
	# Draw status text
	for i in range(status_text.size()):
		var text = status_text[i]
		var pos = status_pos + Vector2(0, i * 20)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	
	# Draw legend
	var legend_pos = Vector2(10, get_viewport_rect().size.y - 120)
	var legend_text = [
		"Controls:",
		"Space - Test corners",
		"T - Toggle auto-test", 
		"R - Reset position",
		"1/2/3 - Set speed"
	]
	
	for i in range(legend_text.size()):
		var text = legend_text[i]
		var pos = legend_pos + Vector2(0, i * 15)
		var color = Color.LIGHT_GRAY if i > 0 else Color.WHITE
		draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
