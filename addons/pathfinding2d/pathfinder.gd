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

# Dynamic pathfinding settings
@export var path_validation_rate: float = 0.2  # How often to validate current path (seconds)
@export var auto_recalculate: bool = true  # Automatically recalculate when path becomes invalid

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

# Dynamic pathfinding variables
var path_validation_timer: float = 0.0
var last_path_hash: int = 0
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
	
	_update_dynamic_pathfinding(delta)
	
	if is_moving:
		_update_stuck_detection(delta)
		_follow_path(delta)

func _update_dynamic_pathfinding(delta):
	"""Handle dynamic path validation and recalculation"""
	if not is_moving or current_path.is_empty():
		return
	
	path_validation_timer += delta
	
	# Validate path periodically
	if path_validation_timer >= path_validation_rate:
		path_validation_timer = 0.0
		
		if not is_path_valid():
			print("Path became invalid - requesting recalculation")
			path_invalidated.emit()
			
			if auto_recalculate:
				_attempt_path_recalculation()

func _attempt_path_recalculation():
	"""Attempt to recalculate the path with fallback strategies"""
	var current_time = Time.get_time_dict_from_system().get("second", 0) as float
	if current_time - last_recalc_time < recalc_cooldown:
		return false
	
	last_recalc_time = current_time
	
	# Try recalculating to original destination
	var original_target = target_position
	if current_path.size() > 0:
		original_target = current_path[-1]
	
	print("Attempting automatic path recalculation to: ", original_target)
	
	# Temporarily stop movement to avoid conflicts
	var was_moving = is_moving
	stop_movement()
	
	if find_path_to(original_target):
		print("Successfully recalculated path")
		path_recalculated.emit()
		consecutive_failed_recalcs = 0
		return true
	else:
		consecutive_failed_recalcs += 1
		print("Failed to recalculate path (attempt ", consecutive_failed_recalcs, "/", max_failed_recalcs, ")")
		
		# If we've failed too many times, try alternative strategies
		if consecutive_failed_recalcs >= max_failed_recalcs:
			_try_alternative_pathfinding_strategies()
		else:
			# Resume movement with old path if it exists
			if was_moving and not current_path.is_empty():
				is_moving = true
		
		return false

func _try_alternative_pathfinding_strategies():
	"""Try alternative pathfinding strategies when normal recalculation fails"""
	print("Trying alternative pathfinding strategies...")
	
	# Strategy 1: Try pathfinding to a point closer to current position
	var fallback_targets = _generate_fallback_targets()
	
	for fallback_target in fallback_targets:
		if find_path_to(fallback_target):
			print("Found alternative path to fallback target: ", fallback_target)
			consecutive_failed_recalcs = 0
			return
	
	# Strategy 2: Try moving to the last known good waypoint
	if current_path.size() > path_index + 1:
		var last_good_waypoint = current_path[path_index + 1]
		if find_path_to(last_good_waypoint):
			print("Found path to last good waypoint: ", last_good_waypoint)
			consecutive_failed_recalcs = 0
			return
	
	# Strategy 3: Emergency stop
	print("All pathfinding strategies failed - stopping movement")
	stop_movement()
	path_blocked.emit()
	consecutive_failed_recalcs = 0

func _generate_fallback_targets() -> Array[Vector2]:
	"""Generate fallback target positions for alternative pathfinding"""
	var fallback_targets: Array[Vector2] = []
	var original_target = target_position
	
	# Generate points in a circle around the original target
	var fallback_radius = [50.0, 100.0, 150.0]
	var angle_steps = 8
	
	for radius in fallback_radius:
		for i in angle_steps:
			var angle = (i * TAU) / angle_steps
			var fallback_pos = original_target + Vector2(cos(angle), sin(angle)) * radius
			fallback_targets.append(fallback_pos)
	
	# Sort by distance to current position (closer first)
	fallback_targets.sort_custom(func(a, b): return global_position.distance_squared_to(a) < global_position.distance_squared_to(b))
	
	return fallback_targets

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
	
	# Try different recovery strategies in order
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
	return _attempt_path_recalculation()

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
	
	# Reset stuck detection and path validation
	stuck_timer = 0.0
	is_unsticking = false
	last_positions.clear()
	path_validation_timer = 0.0
	last_path_hash = _calculate_path_hash(path)
	consecutive_failed_recalcs = 0
	
	print("Pathfinder: Path found with ", path.size(), " waypoints")
	path_found.emit(current_path)
	return true

func _calculate_path_hash(path: PackedVector2Array) -> int:
	"""Calculate a hash for the path to detect changes"""
	var hash_string = ""
	for point in path:
		hash_string += str(int(point.x)) + "," + str(int(point.y)) + ";"
	return hash_string.hash()

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
	path_validation_timer = 0.0

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
	path_validation_timer = 0.0
	consecutive_failed_recalcs = 0
	print("Pathfinder: Destination reached!")
	destination_reached.emit()

func get_current_path() -> PackedVector2Array:
	return current_path

func is_path_valid() -> bool:
	if not system or current_path.is_empty():
		return false
	
	# Check if any segment of the remaining path is blocked
	for i in range(path_index, current_path.size() - 1):
		var start = current_path[i]
		var end = current_path[i + 1]
		
		if system._is_circle_position_unsafe(start, agent_radius) or \
		   system._is_circle_position_unsafe(end, agent_radius) or \
		   not system._is_safe_circle_path(start, end, agent_radius):
			return false
	
	return true

func recalculate_path():
	"""Manually trigger path recalculation"""
	if not is_moving:
		return
	
	_attempt_path_recalculation()

func _draw() -> void:
	if not debug_draw:
		return
	
	# Draw agent circle with status coloring
	var color = agent_color
	if consecutive_failed_recalcs > 0:
		color = Color.PURPLE  # Path recalculation issues
	elif is_unsticking:
		color = Color.ORANGE  # Unsticking
	elif stuck_timer > stuck_time_threshold * 0.7:
		color = Color.YELLOW  # Getting stuck
	elif not is_path_valid() and is_moving:
		color = Color.RED  # Invalid path
	
	draw_circle(Vector2.ZERO, agent_radius, color * 0.7)
	draw_arc(Vector2.ZERO, agent_radius, 0, TAU, 32, color, 2.0)
	
	# Draw current path with validation status
	if current_path.size() > 1:
		for i in range(current_path.size() - 1):
			var start = to_local(current_path[i])
			var end = to_local(current_path[i + 1])
			
			# Color path segments based on validity
			var segment_color = path_color
			if i >= path_index:
				# Check if this segment is still valid
				if system and not system._is_safe_circle_path(current_path[i], current_path[i + 1], agent_radius):
					segment_color = Color.RED
			else:
				segment_color = Color.GRAY  # Already passed
			
			draw_line(start, end, segment_color, 3.0)
		
		# Draw waypoints
		for i in range(current_path.size()):
			var point = to_local(current_path[i])
			var color_waypoint = path_color
			if i == path_index:
				color_waypoint = Color.WHITE  # Current target
			elif i < path_index:
				color_waypoint = Color.GRAY  # Passed waypoints
			draw_circle(point, 5.0, color_waypoint)
	
	# Draw target position
	if is_moving and target_position != Vector2.ZERO:
		var target_local = to_local(target_position)
		draw_circle(target_local, 8.0, Color.MAGENTA)
	
	# Draw dynamic status indicators
	if path_validation_timer > 0:
		# Path validation progress indicator
		var progress = path_validation_timer / path_validation_rate
		var indicator_pos = Vector2(0, -agent_radius - 15)
		var indicator_size = Vector2(20, 3)
		draw_rect(Rect2(indicator_pos - indicator_size * 0.5, indicator_size), Color.BLACK)
		draw_rect(Rect2(indicator_pos - indicator_size * 0.5, Vector2(indicator_size.x * progress, indicator_size.y)), Color.CYAN)
	
	# Draw recalculation failure count
	if consecutive_failed_recalcs > 0:
		var warning_pos = Vector2(agent_radius + 5, -5)
		for i in consecutive_failed_recalcs:
			draw_circle(warning_pos + Vector2(i * 8, 0), 3.0, Color.RED)
	
	# Other existing debug drawing...
	if corner_avoidance_distance > 0:
		draw_arc(Vector2.ZERO, corner_avoidance_distance, 0, TAU, 32, Color.CYAN * 0.3, 1.0)
	
	if is_unsticking and unstuck_direction.length() > 0.1:
		var arrow_end = unstuck_direction * 20
		draw_line(Vector2.ZERO, arrow_end, Color.RED, 3.0)
		var arrow_size = 5.0
		var arrow_angle = 0.5
		draw_line(arrow_end, arrow_end - unstuck_direction.rotated(arrow_angle) * arrow_size, Color.RED, 2.0)
		draw_line(arrow_end, arrow_end - unstuck_direction.rotated(-arrow_angle) * arrow_size, Color.RED, 2.0)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if agent_radius <= 0:
		warnings.append("Agent radius must be greater than 0")
	
	if movement_speed <= 0:
		warnings.append("Movement speed must be greater than 0")
	
	if arrival_distance <= 0:
		warnings.append("Arrival distance must be greater than 0")
	
	if path_validation_rate <= 0:
		warnings.append("Path validation rate must be greater than 0")
	
	if path_validation_rate < 0.1:
		warnings.append("Very low path validation rate may cause performance issues")
	
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

func get_path_validation_progress() -> float:
	return path_validation_timer / path_validation_rate

func get_failed_recalc_count() -> int:
	return consecutive_failed_recalcs

func is_path_being_validated() -> bool:
	return is_moving and current_path.size() > 0
