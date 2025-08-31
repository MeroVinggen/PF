@tool
extends Node2D
class_name Pathfinder

@export var agent_radius: float = 10.0
@export var movement_speed: float = 200.0
@export var rotation_speed: float = 5.0
@export var auto_move: bool = true
@export var debug_draw: bool = true
@export var agent_color: Color = Color.GREEN
@export var path_color: Color = Color.YELLOW
@export var arrival_distance: float = 8.0

# Stuck prevention settings
@export var stuck_threshold: float = 2.0
@export var stuck_time_threshold: float = 2.0
@export var unstuck_force: float = 50.0

# Dynamic pathfinding settings
@export var path_validation_rate: float = 0.2
@export var auto_recalculate: bool = true

var system: PathfinderSystem
var current_path: PackedVector2Array = PackedVector2Array()
var target_position: Vector2
var path_index: int = 0
var is_moving: bool = false

# Stuck detection variables
var last_positions: Array[Vector2] = []
var stuck_timer: float = 0.0
var unstuck_direction: Vector2 = Vector2.ZERO
var is_unsticking: bool = false

# Dynamic pathfinding variables
var path_validation_timer: float = 0.0
var consecutive_failed_recalcs: int = 0
var max_failed_recalcs: int = 3

signal path_found(path: PackedVector2Array)
signal destination_reached()
signal path_blocked()
signal agent_stuck()
signal agent_unstuck()
signal path_invalidated()
signal path_recalculated()

func _ready():
	add_to_group("pathfinders")
	if not Engine.is_editor_hint():
		call_deferred("_find_system")

func _find_system():
	system = get_tree().get_first_node_in_group("pathfinder_systems") as PathfinderSystem
	if system:
		system.register_pathfinder(self)
		print("Pathfinder connected to system")
	else:
		print("Warning: No PathfinderSystem found!")
		await get_tree().create_timer(0.1).timeout
		_find_system()

func _exit_tree():
	if system and not Engine.is_editor_hint():
		system.unregister_pathfinder(self)

func _physics_process(delta: float) -> void:
	queue_redraw()

func _process(delta):
	if Engine.is_editor_hint() or not auto_move:
		return
	
	_update_path_validation(delta)
	
	if is_moving:
		_update_stuck_detection(delta)
		_follow_path(delta)

# SIMPLIFIED: Combined dynamic pathfinding logic
func _update_path_validation(delta):
	if not is_moving or current_path.is_empty():
		return
	
	path_validation_timer += delta
	if path_validation_timer >= path_validation_rate:
		path_validation_timer = 0.0
		
		if not _is_current_path_safe():
			path_invalidated.emit()
			_recalculate_or_find_alternative()

func _recalculate_or_find_alternative():
	consecutive_failed_recalcs += 1
	
	if consecutive_failed_recalcs >= max_failed_recalcs:
		_pause_and_retry()
		return
	
	if system.is_grid_dirty():
		system.force_grid_update()
	
	var path = system.find_path_for_circle(global_position, target_position, agent_radius)
	
	if path.is_empty():
		# Try nearby positions
		var angles = [0, PI/4, PI/2, 3*PI/4, PI, 5*PI/4, 3*PI/2, 7*PI/4]
		for angle in angles:
			var offset = Vector2(cos(angle), sin(angle)) * (agent_radius * 3)
			var test_pos = target_position + offset
			if _is_point_in_bounds(test_pos) and not system._is_circle_position_unsafe(test_pos, agent_radius):
				path = system.find_path_for_circle(global_position, test_pos, agent_radius)
				if not path.is_empty():
					target_position = test_pos
					break
		
		if path.is_empty():
			_pause_and_retry()
			return
	
	current_path = path
	path_index = 0
	consecutive_failed_recalcs = 0
	path_recalculated.emit()

# SIMPLIFIED: Basic path safety check
func _is_current_path_safe() -> bool:
	if not system or current_path.is_empty() or path_index >= current_path.size():
		return false
	
	# Check current position and next waypoint
	if system._is_circle_position_unsafe(global_position, agent_radius):
		return false
	
	if path_index < current_path.size():
		var next_waypoint = current_path[path_index]
		if system._is_circle_position_unsafe(next_waypoint, agent_radius):
			return false
		if not system._is_safe_circle_path(global_position, next_waypoint, agent_radius):
			return false
	
	return true

# SIMPLIFIED: Single recalculation attempt function
func _attempt_path_recalculation():
	if consecutive_failed_recalcs >= max_failed_recalcs:
		print("Too many failures, pausing...")
		_pause_and_retry()
		return
	
	consecutive_failed_recalcs += 1
	
	if system.is_grid_dirty():
		system.force_grid_update()
	
	var path = system.find_path_for_circle(global_position, target_position, agent_radius)
	
	if not path.is_empty():
		current_path = path
		path_index = 0
		consecutive_failed_recalcs = 0
		path_recalculated.emit()
		print("Path recalculated successfully")
	else:
		print("Recalculation failed, trying alternatives...")
		_try_alternative_solutions()

# SIMPLIFIED: Alternative solutions
func _try_alternative_solutions():
	# Try nearby positions around target
	var angles = [0, PI/4, PI/2, 3*PI/4, PI, 5*PI/4, 3*PI/2, 7*PI/4]
	
	for angle in angles:
		var offset = Vector2(cos(angle), sin(angle)) * (agent_radius * 3)
		var test_pos = target_position + offset
		
		if _is_point_in_bounds(test_pos) and not system._is_circle_position_unsafe(test_pos, agent_radius):
			var path = system.find_path_for_circle(global_position, test_pos, agent_radius)
			if not path.is_empty():
				current_path = path
				path_index = 0
				target_position = test_pos
				consecutive_failed_recalcs = 0
				print("Found alternative path")
				return
	
	_pause_and_retry()

func _pause_and_retry():
	is_moving = false
	consecutive_failed_recalcs = 0
	
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(func(): 
		print("Retrying pathfinding...")
		if find_path_to(target_position):
			print("Retry successful")
	)

func _is_point_in_bounds(point: Vector2) -> bool:
	return _is_point_in_polygon(point, system.bounds_polygon)

func _is_point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return true

	var inside = false
	var j = polygon.size() - 1

	for i in polygon.size():
		var pi = polygon[i]
		var pj = polygon[j]

		if ((pi.y > point.y) != (pj.y > point.y)) and \
			(point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x):
			inside = !inside
		j = i

	return inside

# SIMPLIFIED: Basic stuck detection
func _update_stuck_detection(delta):
	last_positions.append(global_position)
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
		if is_unsticking:
			is_unsticking = false
			agent_unstuck.emit()

func _handle_stuck():
	agent_stuck.emit()
	is_unsticking = true
	
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	directions.shuffle()
	
	for direction in directions:
		var test_pos = global_position + direction * (agent_radius * 2)
		if not system._is_circle_position_unsafe(test_pos, agent_radius):
			unstuck_direction = direction
			return
	
	consecutive_failed_recalcs = 0
	_recalculate_or_find_alternative()

func find_path_to(destination: Vector2) -> bool:
	if not system:
		return false
	
	var path = system.find_path_for_circle(global_position, destination, agent_radius)
	
	if path.is_empty():
		path_blocked.emit()
		return false
	
	current_path = path
	target_position = destination
	path_index = 0
	is_moving = true
	
	# Reset state
	stuck_timer = 0.0
	is_unsticking = false
	last_positions.clear()
	path_validation_timer = 0.0
	consecutive_failed_recalcs = 0
	
	path_found.emit(current_path)
	return true

func move_to(destination: Vector2):
	if find_path_to(destination):
		is_moving = true

func stop_movement():
	is_moving = false
	current_path.clear()
	path_index = 0
	is_unsticking = false
	stuck_timer = 0.0

func _follow_path(delta):
	if current_path.is_empty() or path_index >= current_path.size():
		_on_destination_reached()
		return
	
	# Handle unstuck movement
	if is_unsticking and unstuck_direction.length() > 0.1:
		_apply_unstuck_movement(delta)
		return
	
	var current_target = current_path[path_index]
	var distance_to_target = global_position.distance_to(current_target)
	
	# Check if reached waypoint
	if distance_to_target < arrival_distance:
		path_index += 1
		if path_index >= current_path.size():
			_on_destination_reached()
			return
		current_target = current_path[path_index]
		distance_to_target = global_position.distance_to(current_target)
	
	# Move towards target
	var direction = (current_target - global_position).normalized()
	var movement = direction * movement_speed * delta
	
	if movement.length() > distance_to_target:
		movement = direction * distance_to_target
	
	global_position += movement
	
	# Rotate towards movement direction
	if direction.length() > 0.1:
		var target_angle = direction.angle()
		rotation = lerp_angle(rotation, target_angle, rotation_speed * delta)

func _apply_unstuck_movement(delta):
	var movement = unstuck_direction * unstuck_force * delta
	var new_position = global_position + movement
	
	if not system._is_circle_position_unsafe(new_position, agent_radius):
		global_position = new_position
	else:
		unstuck_direction = unstuck_direction.rotated(PI / 4)

func _on_destination_reached():
	is_moving = false
	current_path.clear()
	path_index = 0
	is_unsticking = false
	stuck_timer = 0.0
	consecutive_failed_recalcs = 0
	destination_reached.emit()

func get_current_path() -> PackedVector2Array:
	return current_path

func is_path_valid() -> bool:
	return _is_current_path_safe()

func recalculate_path():
	if is_moving:
		_attempt_path_recalculation()

func _draw() -> void:
	if not debug_draw:
		return
	
	# Draw agent with status color
	var color = agent_color
	if consecutive_failed_recalcs > 0:
		color = Color.PURPLE
	elif is_unsticking:
		color = Color.ORANGE
	elif stuck_timer > stuck_time_threshold * 0.7:
		color = Color.YELLOW
	
	draw_circle(Vector2.ZERO, agent_radius, color * 0.7)
	draw_arc(Vector2.ZERO, agent_radius, 0, TAU, 32, color, 2.0)
	
	# Draw path
	if current_path.size() > 1:
		for i in range(current_path.size() - 1):
			var start = to_local(current_path[i])
			var end = to_local(current_path[i + 1])
			var segment_color = path_color if i >= path_index else Color.GRAY
			draw_line(start, end, segment_color, 3.0)
		
		# Draw waypoints
		for i in range(current_path.size()):
			var point = to_local(current_path[i])
			var waypoint_color = Color.WHITE if i == path_index else (Color.GRAY if i < path_index else path_color)
			draw_circle(point, 5.0, waypoint_color)
	
	# Draw target
	if is_moving and target_position != Vector2.ZERO:
		draw_circle(to_local(target_position), 8.0, Color.MAGENTA)
	
	# Draw unstuck direction
	if is_unsticking and unstuck_direction.length() > 0.1:
		var arrow_end = unstuck_direction * 20
		draw_line(Vector2.ZERO, arrow_end, Color.RED, 3.0)

# Helper functions
func get_distance_to_target() -> float:
	if current_path.is_empty() or path_index >= current_path.size():
		return 0.0
	return global_position.distance_to(current_path[path_index])

func get_distance_to_destination() -> float:
	return global_position.distance_to(target_position) if target_position != Vector2.ZERO else 0.0

func is_stuck() -> bool:
	return stuck_timer >= stuck_time_threshold
