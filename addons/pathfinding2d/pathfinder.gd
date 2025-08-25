@tool
extends Node2D
class_name Pathfinder

# Agent polygon should be centered around origin for proper collision detection
@export var agent_polygon: PackedVector2Array = PackedVector2Array([
	Vector2(-5, -5),
	Vector2(5, -5),
	Vector2(5, 5),
	Vector2(-5, 5)
])

@export var movement_speed: float = 200.0
@export var rotation_speed: float = 5.0
@export var auto_move: bool = true
@export var debug_draw: bool = true
@export var agent_color: Color = Color.GREEN
@export var path_color: Color = Color.YELLOW
@export var arrival_distance: float = 8.0  # Reduced for better precision

var system: PathfinderSystem
var current_path: PackedVector2Array = PackedVector2Array()
var target_position: Vector2
var path_index: int = 0
var is_moving: bool = false

signal path_found(path: PackedVector2Array)
signal destination_reached()
signal path_blocked()

func _ready():
	add_to_group("pathfinders")
	if not Engine.is_editor_hint():
		# Use call_deferred to ensure all nodes are ready
		call_deferred("_find_system")

func _find_system():
	system = get_tree().get_first_node_in_group("pathfinder_systems") as PathfinderSystem
	if system:
		system.register_pathfinder(self)
		print("Pathfinder connected to system")
	else:
		print("Warning: No PathfinderSystem found!")
		# Try again after a short delay
		await get_tree().create_timer(0.1).timeout
		_find_system()

func _exit_tree():
	if system and not Engine.is_editor_hint():
		system.unregister_pathfinder(self)

func _process(delta):
	if Engine.is_editor_hint() or not auto_move or not is_moving:
		return
	
	_follow_path(delta)

func find_path_to(destination: Vector2) -> bool:
	if not system:
		print("No pathfinding system available")
		return false
	
	print("Pathfinder requesting path to: ", destination)
	var path = system.find_path(global_position, destination, agent_polygon)
	
	if path.is_empty():
		print("Pathfinder: No path found")
		path_blocked.emit()
		return false
	
	current_path = path
	target_position = destination
	path_index = 0
	is_moving = true
	
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

func _follow_path(delta):
	if current_path.is_empty() or path_index >= current_path.size():
		_on_destination_reached()
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
	
	# Additional safety check - validate current position isn't blocked
	if system and system._is_position_blocked(global_position, agent_polygon):
		print("Agent is in blocked position! Recalculating path...")
		recalculate_path()
		return
	
	# Move towards current target
	var direction = (current_target - global_position).normalized()
	var movement = direction * movement_speed * delta
	
	# Don't overshoot the target
	if movement.length() > distance_to_target:
		movement = direction * distance_to_target
	
	# Validate the movement won't put us in a blocked position
	var new_position = global_position + movement
	if system and system._is_position_blocked(new_position, agent_polygon):
		print("Movement would cause collision! Recalculating path...")
		recalculate_path()
		return
	
	global_position = new_position
	
	# Rotate towards movement direction
	if direction.length() > 0.1:
		var target_angle = direction.angle()
		rotation = lerp_angle(rotation, target_angle, rotation_speed * delta)

func _on_destination_reached():
	is_moving = false
	current_path.clear()
	path_index = 0
	print("Pathfinder: Destination reached!")
	destination_reached.emit()

func get_current_path() -> PackedVector2Array:
	return current_path

func is_path_valid() -> bool:
	if not system or current_path.is_empty():
		return false
	
	# Check if current path is still valid (no new obstacles in the way)
	for i in range(current_path.size() - 1):
		var start = current_path[i]
		var end = current_path[i + 1]
		
		if system._is_position_blocked(start, agent_polygon) or \
		   system._is_position_blocked(end, agent_polygon) or \
		   not system._is_line_clear(start, end, agent_polygon):
			return false
	
	return true

func recalculate_path():
	if not is_moving:
		return
	
	var destination = target_position
	if current_path.size() > path_index:
		destination = current_path[-1]  # Use the final destination
	
	print("Recalculating path from current position")
	find_path_to(destination)

func get_agent_bounds() -> Rect2:
	if agent_polygon.is_empty():
		return Rect2()
	
	var min_x = agent_polygon[0].x
	var max_x = agent_polygon[0].x
	var min_y = agent_polygon[0].y
	var max_y = agent_polygon[0].y
	
	for point in agent_polygon:
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)
	
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

func _draw():
	if not debug_draw:
		return
	
	# Draw agent polygon
	if agent_polygon.size() >= 3:
		draw_colored_polygon(agent_polygon, agent_color * 0.7)
		var outline = agent_polygon + PackedVector2Array([agent_polygon[0]])
		draw_polyline(outline, agent_color, 2.0)
	else:
		# Fallback to circle if polygon is invalid
		draw_circle(Vector2.ZERO, 8.0, agent_color)
	
	# Draw current path
	if current_path.size() > 1:
		for i in range(current_path.size() - 1):
			var start = to_local(current_path[i])
			var end = to_local(current_path[i + 1])
			draw_line(start, end, path_color, 3.0)
		
		# Draw waypoints
		for i in range(current_path.size()):
			var point = to_local(current_path[i])
			var color = path_color
			if i == path_index:
				color = Color.WHITE  # Highlight current target
			elif i < path_index:
				color = Color.GRAY  # Completed waypoints
			draw_circle(point, 5.0, color)
	
	# Draw target position
	if is_moving and target_position != Vector2.ZERO:
		var target_local = to_local(target_position)
		draw_circle(target_local, 8.0, Color.MAGENTA)
	
	# Draw arrival distance around current target
	if is_moving and path_index < current_path.size():
		var current_target_local = to_local(current_path[path_index])
		draw_arc(current_target_local, arrival_distance, 0, TAU, 16, Color.CYAN, 1.0)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if agent_polygon.size() < 3:
		warnings.append("Agent polygon needs at least 3 points")
	
	if movement_speed <= 0:
		warnings.append("Movement speed must be greater than 0")
	
	if arrival_distance <= 0:
		warnings.append("Arrival distance must be greater than 0")
	
	# Check if polygon is properly centered
	var centroid = Vector2.ZERO
	for point in agent_polygon:
		centroid += point
	centroid /= agent_polygon.size()
	
	if centroid.distance_to(Vector2.ZERO) > 2.0:
		warnings.append("Agent polygon should be centered around origin (0,0) for proper collision detection")
	
	return warnings

# Helper functions for external use
func get_distance_to_target() -> float:
	if current_path.is_empty() or path_index >= current_path.size():
		return 0.0
	return global_position.distance_to(current_path[path_index])

func get_distance_to_destination() -> float:
	if target_position == Vector2.ZERO:
		return 0.0
	return global_position.distance_to(target_position)
