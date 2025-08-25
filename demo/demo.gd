# Enhanced debug demo script for testing the pathfinding system
extends Node2D

@onready var pathfinder_system = $PathfinderSystem
@onready var pathfinder = $Pathfinder
@onready var obstacle1 = $PathfinderObstacle
@onready var obstacle2 = $PathfinderObstacle2

func _ready():
	print("=== Pathfinding Demo Starting ===")
	
	# Wait a moment for all nodes to be ready
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Connect pathfinder signals
	if pathfinder:
		pathfinder.path_found.connect(_on_path_found)
		pathfinder.destination_reached.connect(_on_destination_reached)
		pathfinder.path_blocked.connect(_on_path_blocked)
		print("Pathfinder signals connected")
	
	# Debug system state
	_debug_system_state()
	
	print("=== Demo Ready ===")
	print("Click anywhere to make the agent pathfind to that location")
	print("Press SPACE to test a simple path")

func _debug_system_state():
	print("\n--- System Debug Info ---")
	
	if pathfinder_system:
		print("PathfinderSystem found at: ", pathfinder_system.global_position)
		print("Bounds polygon: ", pathfinder_system.bounds_polygon)
		print("Grid size: ", pathfinder_system.grid_size)
		print("Grid points: ", pathfinder_system.grid.size())
		print("Obstacles registered: ", pathfinder_system.obstacles.size())
		print("Pathfinders registered: ", pathfinder_system.pathfinders.size())
	else:
		print("ERROR: PathfinderSystem not found!")
	
	if pathfinder:
		print("Pathfinder found at: ", pathfinder.global_position)
		print("Agent polygon: ", pathfinder.agent_polygon)
		print("System reference: ", pathfinder.system)
	else:
		print("ERROR: Pathfinder not found!")
	
	if obstacle1:
		print("Obstacle1 at: ", obstacle1.global_position)
		print("Obstacle1 polygon: ", obstacle1.obstacle_polygon)
	
	if obstacle2:
		print("Obstacle2 at: ", obstacle2.global_position)
		print("Obstacle2 polygon: ", obstacle2.obstacle_polygon)
	
	print("--- End Debug Info ---\n")

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var target = get_global_mouse_position()
		print("\n=== Click Event ===")
		print("Target position: ", target)
		print("Pathfinder position: ", pathfinder.global_position if pathfinder else "N/A")
		
		if pathfinder:
			pathfinder.move_to(target)
		else:
			print("ERROR: No pathfinder available")
	
	# Test with SPACE key
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		print("\n=== Space Key Test ===")
		_test_simple_path()
	
	# Debug info with D key
	elif event is InputEventKey and event.pressed and event.keycode == KEY_D:
		_debug_system_state()

func _test_simple_path():
	if not pathfinder or not pathfinder_system:
		print("Missing components for test")
		return
	
	# Test a simple path that should definitely work
	var start = Vector2(100, 100)
	var end = Vector2(400, 400)
	
	print("Testing path from ", start, " to ", end)
	
	# Move pathfinder to start position
	pathfinder.global_position = start
	
	# Try to find path
	var path = pathfinder_system.find_path(start, end, pathfinder.agent_polygon)
	if path.is_empty():
		print("Test failed: No path found")
	else:
		print("Test success: Path found with ", path.size(), " points")
		print("Path: ", path)

func _on_path_found(path: PackedVector2Array):
	print("✓ Path found with ", path.size(), " waypoints")
	print("Path points: ", path)

func _on_destination_reached():
	print("✓ Destination reached!")

func _on_path_blocked():
	print("✗ No path available to target!")

# Debug drawing
func _draw():
	# Draw some helpful debug info
	if pathfinder_system and pathfinder_system.debug_draw:
		# Draw grid bounds
		var bounds = pathfinder_system._get_bounds_rect()
		draw_rect(bounds, Color.CYAN, false, 2.0)
	
	# Draw click target indicator
	if Input.is_action_pressed("ui_accept"):  # Any key held
		var mouse_pos = get_global_mouse_position()
		draw_circle(to_local(mouse_pos), 10, Color.MAGENTA)
