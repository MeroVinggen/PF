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
@export var corner_avoidance_distance: float = 20.0

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
var last_recalc_time: float = 0.0
var recalc_cooldown: float = 1.0

signal path_found(path: PackedVector2Array)
signal destination_reached()
signal path_blocked()
signal agent_stuck()
signal agent_unstuck()

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

# fix this
func _physics_process(delta: float) -> void:
	queue_redraw()

	
func _process(delta):
	if Engine.is_editor_hint() or not auto_move or not is_moving:
		return
	
	_update_stuck_detection(delta)
	_follow_path(delta)

func _update_stuck_detection(delta):
	"""Monitor for stuck situations and handle recovery"""
	last_positions.append(global_position)
	if last_positions.size() > 10:
		last_positions.pop_front()
	
	if last_positions.size() < 5:
		return
	
	var recent_movement = last_positions[-1].distance_to(last_positions[0])
	
	if recent_movement < stuck_threshold and not is_unsticking:
		stuck_timer += delta
		if stuck_timer >= stuck_time_threshold:
			_handle_stuck_situation()
	else:
		if stuck_timer > 0:
			stuck_timer = 0.0
			if is_unsticking:
				is_unsticking = false
				agent_unstuck.emit()
				print("Agent successfully unstuck")

func _handle_stuck_situation():
	"""Handle when the agent gets stuck"""
	print("Agent appears stuck! Attempting recovery...")
	agent_stuck.emit()
	is_unsticking = true
	
	if not _try_corner_avoidance():
		if not _try_path_recalculation():
			_try_emergency_movement()

func _try_corner_avoidance() -> bool:
	"""Try to move away from nearby corners"""
	if not system:
		return false
	
	var avoidance_force = Vector2.ZERO
	var found_corner = false
	
	for obstacle in system.obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var world_poly = obstacle.get_world_polygon()
		var corners = system._find_obstacle_corners(world_poly)
		
		for corner in corners:
			var distance = global_position.distance_to(corner)
			if distance < corner_avoidance_distance:
				found_corner = true
				var repulsion = (global_position - corner).normalized()
				var strength = (corner_avoidance_distance - distance) / corner_avoidance_distance
				avoidance_force += repulsion * strength * unstuck_force
	
	if found_corner:
		unstuck_direction = avoidance_force.normalized()
		print("Applying corner avoidance force: ", unstuck_direction)
		return true
	
	return false

func _try_path_recalculation() -> bool:
	"""Try recalculating the path"""
	var current_time = Time.get_time_dict_from_system().get("second", 0) as float
	if current_time - last_recalc_time < recalc_cooldown:
		return false
	
	last_recalc_time = current_time
	print("Attempting path recalculation...")
	
	var original_target = target_position
	if current_path.size() > path_index:
		original_target = current_path[-1]
	
	stop_movement()
	
	if find_path_to(original_target):
		print("Successfully recalculated path")
		return true
	
	return false

func _try_emergency_movement():
	"""Last resort: try random movement directions"""
	print("Using emergency movement to get unstuck")
	
	var directions = [
		Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT,
		Vector2.UP + Vector2.LEFT, Vector2.UP + Vector2.RIGHT,
		Vector2.DOWN + Vector2.LEFT, Vector2.DOWN + Vector2.RIGHT
	]
	
	for direction in directions:
		var test_pos = global_position + direction * unstuck_force
		if system and not system._is_circle_position_unsafe(test_pos, agent_radius):
			unstuck_direction = direction
			print("Found emergency direction: ", direction)
			return
	
	if last_positions.size() >= 2:
		var last_movement = last_positions[-1] - last_positions[-2]
		unstuck_direction = -last_movement.normalized()
	else:
		unstuck_direction = Vector2.UP

func find_path_to(destination: Vector2) -> bool:
	if not system:
		print("No pathfinding system available")
		return false
	
	print("Pathfinder requesting path to: ", destination)
	var path = system.find_path_for_circle(global_position, destination, agent_radius)
	
	if path.is_empty():
		print("Pathfinder: No path found")
		path_blocked.emit()
		return false
	
	current_path = path
	target_position = destination
	path_index = 0
	is_moving = true
	
	# Reset stuck detection
	stuck_timer = 0.0
	is_unsticking = false
	last_positions.clear()
	
	print("Pathfinder: Path found with ", path.size(), " waypoints")
	path_found.emit(current_path)
	return true

func move_to(destination: Vector2):
	if find_path_to(destination):
		is_moving = true
	else:
		print("No path found to destination")

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
	
	# Check if we've reached the current waypoint
	if distance_to_target < arrival_distance:
		path_index += 1
		if path_index >= current_path.size():
			_on_destination_reached()
			return
		current_target = current_path[path_index]
		distance_to_target = global_position.distance_to(current_target)
	
	# Enhanced collision prediction
	if system and _will_movement_cause_collision(current_target, delta):
		print("Movement would cause collision! Handling...")
		_handle_collision_avoidance(current_target, delta)
		return
	
	# Normal movement
	var direction = (current_target - global_position).normalized()
	var movement = direction * movement_speed * delta
	
	# Don't overshoot the target
	if movement.length() > distance_to_target:
		movement = direction * distance_to_target
	
	# Apply corner avoidance force if near corners
	var avoidance_force = _calculate_corner_avoidance_force()
	if avoidance_force.length() > 0.1:
		direction = (direction + avoidance_force * 0.5).normalized()
		movement = direction * movement_speed * delta
		if movement.length() > distance_to_target:
			movement = direction * distance_to_target
	
	global_position += movement
	
	# Rotate towards movement direction
	if direction.length() > 0.1:
		var target_angle = direction.angle()
		rotation = lerp_angle(rotation, target_angle, rotation_speed * delta)

func _apply_unstuck_movement(delta):
	"""Apply movement to get unstuck"""
	var movement = unstuck_direction * unstuck_force * delta
	var new_position = global_position + movement
	
	if system and not system._is_circle_position_unsafe(new_position, agent_radius):
		global_position = new_position
		print("Applied unstuck movement")
	else:
		unstuck_direction = unstuck_direction.rotated(PI / 4)
		print("Rotated unstuck direction")

func _will_movement_cause_collision(target: Vector2, delta: float) -> bool:
	"""Predict if movement towards target will cause collision"""
	if not system:
		return false
	
	var direction = (target - global_position).normalized()
	var movement = direction * movement_speed * delta
	var future_position = global_position + movement
	
	return system._is_circle_position_unsafe(future_position, agent_radius)

func _handle_collision_avoidance(target: Vector2, delta: float):
	"""Handle collision avoidance when direct movement is blocked"""
	var direction_to_target = (target - global_position).normalized()
	var perpendicular_dirs = [
		Vector2(-direction_to_target.y, direction_to_target.x),
		Vector2(direction_to_target.y, -direction_to_target.x)
	]
	
	for perp_dir in perpendicular_dirs:
		var slide_movement = perp_dir * movement_speed * delta * 0.7
		var test_position = global_position + slide_movement
		
		if system and not system._is_circle_position_unsafe(test_position, agent_radius):
			global_position = test_position
			print("Applied collision avoidance sliding")
			return
	
	var reduced_movement = direction_to_target * movement_speed * delta * 0.3
	var test_position = global_position + reduced_movement
	
	if system and not system._is_circle_position_unsafe(test_position, agent_radius):
		global_position = test_position
	else:
		_handle_stuck_situation()

func _calculate_corner_avoidance_force() -> Vector2:
	"""Calculate force to avoid nearby corners"""
	if not system:
		return Vector2.ZERO
	
	var avoidance_force = Vector2.ZERO
	
	for obstacle in system.obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var world_poly = obstacle.get_world_polygon()
		var corners = system._find_obstacle_corners(world_poly)
		
		for corner in corners:
			var distance = global_position.distance_to(corner)
			if distance < corner_avoidance_distance:
				var repulsion = (global_position - corner).normalized()
				var strength = (corner_avoidance_distance - distance) / corner_avoidance_distance
				avoidance_force += repulsion * strength
	
	return avoidance_force.normalized()

func _on_destination_reached():
	is_moving = false
	current_path.clear()
	path_index = 0
	is_unsticking = false
	stuck_timer = 0.0
	print("Pathfinder: Destination reached!")
	destination_reached.emit()

func get_current_path() -> PackedVector2Array:
	return current_path

func is_path_valid() -> bool:
	if not system or current_path.is_empty():
		return false
	
	for i in range(path_index, current_path.size() - 1):
		var start = current_path[i]
		var end = current_path[i + 1]
		
		if system._is_circle_position_unsafe(start, agent_radius) or \
		   system._is_circle_position_unsafe(end, agent_radius) or \
		   not system._is_safe_circle_path(start, end, agent_radius):
			return false
	
	return true

func recalculate_path():
	if not is_moving:
		return
	
	var destination = target_position
	if current_path.size() > path_index:
		destination = current_path[-1]
	
	print("Recalculating path from current position")
	find_path_to(destination)

func _draw() -> void:
	if not debug_draw:
		return
	
	# Draw agent circle
	var color = agent_color
	if is_unsticking:
		color = Color.ORANGE
	elif stuck_timer > stuck_time_threshold * 0.7:
		color = Color.YELLOW
	
	draw_circle(Vector2.ZERO, agent_radius, color * 0.7)
	draw_arc(Vector2.ZERO, agent_radius, 0, TAU, 32, color, 2.0)
	
	# Draw current path
	if current_path.size() > 1:
		for i in range(current_path.size() - 1):
			var start = to_local(current_path[i])
			var end = to_local(current_path[i + 1])
			draw_line(start, end, path_color, 3.0)
		
		# Draw waypoints
		for i in range(current_path.size()):
			var point = to_local(current_path[i])
			var color_waypoint = path_color
			if i == path_index:
				color_waypoint = Color.WHITE
			elif i < path_index:
				color_waypoint = Color.GRAY
			draw_circle(point, 5.0, color_waypoint)
	
	# Draw target position
	if is_moving and target_position != Vector2.ZERO:
		var target_local = to_local(target_position)
		draw_circle(target_local, 8.0, Color.MAGENTA)
	
	# Draw corner avoidance radius
	if corner_avoidance_distance > 0:
		draw_arc(Vector2.ZERO, corner_avoidance_distance, 0, TAU, 32, Color.CYAN * 0.3, 1.0)
	
	# Draw unstuck direction
	if is_unsticking and unstuck_direction.length() > 0.1:
		var arrow_end = unstuck_direction * 20
		draw_line(Vector2.ZERO, arrow_end, Color.RED, 3.0)
		var arrow_size = 5.0
		var arrow_angle = 0.5
		draw_line(arrow_end, arrow_end - unstuck_direction.rotated(arrow_angle) * arrow_size, Color.RED, 2.0)
		draw_line(arrow_end, arrow_end - unstuck_direction.rotated(-arrow_angle) * arrow_size, Color.RED, 2.0)
	
	# Draw stuck detection progress bar
	#if stuck_timer > 0:
		#var progress = stuck_timer / stuck_time_threshold
		#var bar_width = 30.0
		#var bar_height = 4.0
		#var bar_pos = Vector2(-bar_width * 0.5, -agent_radius - 10)
		#
		#draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color.BLACK)
		#draw_rect(Rect2(bar_pos, Vector2(bar_width * progress, bar_height)), Color.RED)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if agent_radius <= 0:
		warnings.append("Agent radius must be greater than 0")
	
	if movement_speed <= 0:
		warnings.append("Movement speed must be greater than 0")
	
	if arrival_distance <= 0:
		warnings.append("Arrival distance must be greater than 0")
	
	if stuck_time_threshold <= 0:
		warnings.append("Stuck time threshold must be greater than 0")
	
	return warnings

# Helper functions
func get_distance_to_target() -> float:
	if current_path.is_empty() or path_index >= current_path.size():
		return 0.0
	return global_position.distance_to(current_path[path_index])

func get_distance_to_destination() -> float:
	if target_position == Vector2.ZERO:
		return 0.0
	return global_position.distance_to(target_position)

func is_stuck() -> bool:
	return stuck_timer >= stuck_time_threshold

func get_stuck_progress() -> float:
	return stuck_timer / stuck_time_threshold
