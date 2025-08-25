# Example usage script for testing the pathfinding system
# Attach this to a main scene node

extends Node2D

@onready var pathfinder_system = $PathfinderSystem
@onready var pathfinder = $Pathfinder
@onready var obstacle1 = $PathfinderObstacle
@onready var obstacle2 = $PathfinderObstacle2

func _ready():
	# Connect pathfinder signals
	pathfinder.path_found.connect(_on_path_found)
	pathfinder.destination_reached.connect(_on_destination_reached)
	pathfinder.path_blocked.connect(_on_path_blocked)
	
	print("Pathfinding system initialized!")
	print("Click anywhere to make the agent pathfind to that location")

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var target = get_global_mouse_position()
		print("Finding path to: ", target)
		pathfinder.move_to(target)

func _on_path_found(path: PackedVector2Array):
	print("Path found with ", path.size(), " waypoints")

func _on_destination_reached():
	print("Destination reached!")

func _on_path_blocked():
	print("No path available to target!")

# Additional example functions
func example_setup_complex_obstacles():
	# Create a maze-like setup
	var maze_obstacles = []
	
	# Vertical walls
	for i in range(-3, 4):
		var wall = PathfinderObstacle.new()
		wall.position = Vector2(i * 200, 0)
		wall.obstacle_polygon = PackedVector2Array([
			Vector2(-10, -150),
			Vector2(10, -150),
			Vector2(10, 150),
			Vector2(-10, 150)
		])
		add_child(wall)
		maze_obstacles.append(wall)
	
	print("Complex maze created with ", maze_obstacles.size(), " obstacles")

func example_dynamic_obstacles():
	# Example of moving obstacles
	var moving_obstacle = PathfinderObstacle.new()
	moving_obstacle.position = Vector2(100, 100)
	moving_obstacle.obstacle_polygon = PackedVector2Array([
		Vector2(-25, -25),
		Vector2(25, -25),
		Vector2(25, 25),
		Vector2(-25, 25)
	])
	add_child(moving_obstacle)
	
	# Animate the obstacle
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(moving_obstacle, "position", Vector2(300, 300), 3.0)
	tween.tween_property(moving_obstacle, "position", Vector2(100, 100), 3.0)
