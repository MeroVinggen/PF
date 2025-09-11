extends Node2D
class_name MovementController

signal waypoint_reached()
signal destination_reached()
signal agent_stuck()
signal agent_unstuck()

@export var movement_speed: float = 200.0

# Stuck prevention settings
@export var stuck_threshold: float = 2.0
@export var stuck_time_threshold: float = 2.0
@export var unstuck_force: float = 50.0

var pathfinder: PathfinderAgent
var target_node: Node2D

# current path data
var current_target: Vector2 = Vector2.INF
var direction: Vector2
var distance: float

# Stuck detection variables
var last_positions: Array[Vector2] = []
var stuck_timer: float = 0.0

func _ready():
	if not target_node:
		target_node = get_parent()

func setup(pathfinder_ref: PathfinderAgent, node_to_move: Node2D = null):
	pathfinder = pathfinder_ref
	if node_to_move:
		target_node = node_to_move

func _physics_process(delta: float) -> void:
	if not pathfinder or not target_node:
		return
		
	if pathfinder.is_moving:
		#_update_stuck_detection(delta)
		_follow_path(delta)

func _follow_path(delta):
	var update_current_target = pathfinder.get_next_waypoint()
	
	if update_current_target == current_target:
		distance = pathfinder.global_position.distance_to(current_target)
		make_step(delta)
		return
	
	current_target = update_current_target
	
	if current_target == Vector2.INF:
		destination_reached.emit()
		return
	
	# target point been updated - recalc movement data
	direction = (current_target - pathfinder.global_position).normalized()
	distance = pathfinder.global_position.distance_to(current_target)
	make_step(delta)


func make_step(delta: float) -> void:
	# Close enough to waypoint
	if distance < 5.0:
		pathfinder.advance_to_next_waypoint()
	else:
		pathfinder.global_position += direction * movement_speed * delta

#func _update_stuck_detection(delta):
	#last_positions.append(target_node.global_position)
	#if last_positions.size() > 6:
		#last_positions.pop_front()
	#
	#if last_positions.size() < 3:
		#return
	#
	#var movement = last_positions[-1].distance_to(last_positions[0])
	#if movement < stuck_threshold:
		#stuck_timer += delta
		#if stuck_timer >= stuck_time_threshold:
			#_handle_stuck()
	#else:
		#stuck_timer = 0.0

#func _handle_stuck():
	#agent_stuck.emit()
	#stuck_timer = 0.0
	#pathfinder.consecutive_failed_recalcs = 0
	#pathfinder.recalculate_or_find_alternative()

#func is_stuck() -> bool:
	#return stuck_timer >= stuck_time_threshold
