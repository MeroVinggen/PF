@tool
extends EditorPlugin

func _enter_tree():
	add_custom_type(
		"PathfinderSystem",
		"Node2D",
		preload("res://addons/pathfinding2d/pathfinder_system.gd"),
		preload("res://addons/pathfinding2d/icons/pathfinder_system_icon.svg")
	)
	add_custom_type(
		"PathfinderObstacle",
		"Node2D",
		preload("res://addons/pathfinding2d/pathfinder_obstacle.gd"),
		preload("res://addons/pathfinding2d/icons/pathfinder_obstacle_icon.svg")
	)
	add_custom_type(
		"Pathfinder",
		"Node2D",
		preload("res://addons/pathfinding2d/pathfinder.gd"),
		preload("res://addons/pathfinding2d/icons/pathfinder_icon.svg")
	)

func _exit_tree():
	remove_custom_type("PathfinderSystem")
	remove_custom_type("PathfinderObstacle")
	remove_custom_type("Pathfinder")
