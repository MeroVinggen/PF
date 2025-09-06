# Enhanced demo script showcasing dynamic pathfinding features
extends Node2D

@onready var movement_controller = MovementController.new()
@onready var pathfinder_system = $PathfinderSystem
@onready var pathfinder = $PathfinderAgent
@onready var dynamic_obstacle = $PathfinderObstacleD

func _ready():
	print("=== Enhanced Pathfinding Demo Starting ===")
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	_setup_pathfinder_signals()
	_setup_demo_ui()
	
	# ---- movement_controller
	add_child(movement_controller)
	movement_controller.setup(pathfinder, pathfinder)
	movement_controller.waypoint_reached.connect(_on_waypoint_reached)
	movement_controller.destination_reached.connect(_on_destination_reached)
	movement_controller.agent_stuck.connect(_on_agent_stuck)
	movement_controller.agent_unstuck.connect(_on_agent_unstuck)

func _on_waypoint_reached():
	print("→ Waypoint reached")

func _setup_pathfinder_signals():
	if pathfinder:
		pathfinder.path_found.connect(_on_path_found)
		pathfinder.destination_reached.connect(_on_destination_reached)
		pathfinder.path_blocked.connect(_on_path_blocked)
		pathfinder.agent_stuck.connect(_on_agent_stuck)
		pathfinder.agent_unstuck.connect(_on_agent_unstuck)
		pathfinder.path_invalidated.connect(_on_path_invalidated)
		pathfinder.path_recalculated.connect(_on_path_recalculated)

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
		info.append("Grid: " + str(pathfinder_system.grid_manager.grid.size()))
		info.append("Dynamic: " + str(pathfinder_system.get_dynamic_obstacle_count()))
		info.append("Dirty: " + str(pathfinder_system.is_grid_dirty()))
	
	if pathfinder:
		info.append("Moving: " + str(pathfinder.is_moving))
		info.append("Valid: " + str(pathfinder.is_path_valid()))
		info.append("Failures: " + str(pathfinder.consecutive_failed_recalcs))
		info.append("Stuck: " + str(movement_controller.is_stuck()))
	
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
				reload_current_scene()

func _test_pathfinding_to(target: Vector2):
	print("Moving agent to: ", target)
	
	if pathfinder:
		pathfinder.move_to(target)
	else:
		print("ERROR: No pathfinder available")

func _move_dynamic_obstacle_to(target: Vector2):
	print("=== MOVING DYNAMIC OBSTACLE ===")
	print("From: ", dynamic_obstacle.global_position, " To: ", target)
	
	# Create a smooth movement tween
	var tween = create_tween()
	tween.tween_property(dynamic_obstacle, "global_position", target, 1.0)
	tween.tween_callback(_on_obstacle_movement_complete.bind(target))

func _on_obstacle_movement_complete(target_pos: Vector2):
	print("=== OBSTACLE MOVEMENT COMPLETE ===")
	print("Dynamic obstacle now at: ", dynamic_obstacle.global_position)
	print("Target was: ", target_pos)
	print("Distance from target: ", dynamic_obstacle.global_position.distance_to(target_pos))
	
	# Force a grid update after movement
	if pathfinder_system:
		print("Forcing grid update after obstacle movement")
		pathfinder_system.force_grid_update()

func reload_current_scene():
	get_tree().reload_current_scene()

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
