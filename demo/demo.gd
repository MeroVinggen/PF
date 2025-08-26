# Simple demo script for pathfinding testing
extends Node2D

@onready var pathfinder_system = $PathfinderSystem
@onready var pathfinder = $Pathfinder

func _ready():
	print("=== Pathfinding Demo Starting ===")
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	_setup_pathfinder_signals()
	
	print("=== Demo Ready ===")
	print("Left Click - Move to position")

func _setup_pathfinder_signals():
	if pathfinder:
		pathfinder.path_found.connect(_on_path_found)
		pathfinder.destination_reached.connect(_on_destination_reached)
		pathfinder.path_blocked.connect(_on_path_blocked)
		pathfinder.agent_stuck.connect(_on_agent_stuck)
		pathfinder.agent_unstuck.connect(_on_agent_unstuck)
		print("All pathfinder signals connected")

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var target = get_global_mouse_position()
		_test_pathfinding_to(target)

func _test_pathfinding_to(target: Vector2):
	print("Moving to: ", target)
	
	if pathfinder:
		pathfinder.move_to(target)
	else:
		print("ERROR: No pathfinder available")

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
