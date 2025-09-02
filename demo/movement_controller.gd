extends Node2D
class_name MovementController

@export var movement_speed: float = 200.0
@export var rotation_speed: float = 5.0
@export var arrival_distance: float = 8.0

# Stuck prevention settings
@export var stuck_threshold: float = 2.0
@export var stuck_time_threshold: float = 2.0
@export var unstuck_force: float = 50.0

var pathfinder: Pathfinder
var target_node: Node2D

# Stuck detection variables
var last_positions: Array[Vector2] = []
var stuck_timer: float = 0.0

signal waypoint_reached()
signal destination_reached()
signal agent_stuck()
signal agent_unstuck()

func _ready():
	if not target_node:
		target_node = get_parent()

func setup(pathfinder_ref: Pathfinder, node_to_move: Node2D = null):
	pathfinder = pathfinder_ref
	if node_to_move:
		target_node = node_to_move

func _physics_process(delta: float) -> void:
	if not pathfinder or not target_node:
		return
		
	if pathfinder.is_moving:
		_update_stuck_detection(delta)
		_follow_path(delta)

func _follow_path(delta):
	var current_target = pathfinder.get_next_waypoint()
	if current_target == Vector2.INF:
		destination_reached.emit()
		return
	
	var distance_to_target = target_node.global_position.distance_to(current_target)
	
	# Check if reached waypoint
	if distance_to_target < arrival_distance:
		waypoint_reached.emit()
		if not pathfinder.advance_to_next_waypoint():
			destination_reached.emit()
			return
		current_target = pathfinder.get_next_waypoint()
		if current_target == Vector2.INF:
			destination_reached.emit()
			return
		distance_to_target = target_node.global_position.distance_to(current_target)
	
	# Move towards target
	var direction = (current_target - target_node.global_position).normalized()
	var movement = direction * movement_speed * delta
	
	if movement.length() > distance_to_target:
		movement = direction * distance_to_target
	
	target_node.global_position += movement
	
	# Rotate towards movement direction
	if direction.length() > 0.1:
		var target_angle = direction.angle()
		target_node.rotation = lerp_angle(target_node.rotation, target_angle, rotation_speed * delta)

func _update_stuck_detection(delta):
	last_positions.append(target_node.global_position)
	if last_positions.size() > 6:
		last_positions.pop_front()
	
	if last_positions.size() < 3:
		return
	
	var movement = last_positions[-1].distance_to(last_positions[0])
	if movement < stuck_threshold:
		stuck_timer += delta
		if stuck_timer >= stuck_time_threshold:
			_handle_stuck()
	else:
		stuck_timer = 0.0

func _handle_stuck():
	agent_stuck.emit()
	stuck_timer = 0.0
	pathfinder.consecutive_failed_recalcs = 0
	pathfinder._recalculate_or_find_alternative()

func is_stuck() -> bool:
	return stuck_timer >= stuck_time_threshold
