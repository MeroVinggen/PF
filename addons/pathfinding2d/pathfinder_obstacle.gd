@tool
extends Node2D
class_name PathfinderObstacle

@export var obstacle_polygon: PackedVector2Array = PackedVector2Array([
	Vector2(-25, -25),
	Vector2(25, -25),
	Vector2(25, 25),
	Vector2(-25, 25)
])

@export var debug_draw: bool = true
@export var obstacle_color: Color = Color.RED

var system: PathfinderSystem

func _ready():
	if not Engine.is_editor_hint():
		add_to_group("pathfinder_obstacles")
		_find_system()

func _find_system():
	system = get_tree().get_first_node_in_group("pathfinder_systems") as PathfinderSystem
	if system:
		system.register_obstacle(self)

func _exit_tree():
	if system and not Engine.is_editor_hint():
		system.unregister_obstacle(self)

func get_world_polygon() -> PackedVector2Array:
	var world_poly: PackedVector2Array = []
	for point in obstacle_polygon:
		world_poly.append(point + global_position)
	return world_poly

func is_point_inside(point: Vector2) -> bool:
	return _is_point_in_polygon(point - global_position, obstacle_polygon)

func _is_point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return false
	
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

func _draw():
	if not debug_draw:
		return
	
	if obstacle_polygon.size() >= 3:
		# Draw filled polygon
		draw_colored_polygon(obstacle_polygon, obstacle_color * 0.7)
		# Draw outline
		var outline = obstacle_polygon + PackedVector2Array([obstacle_polygon[0]])
		draw_polyline(outline, obstacle_color, 2.0)
	else:
		# Draw as points if not enough vertices
		for point in obstacle_polygon:
			draw_circle(point, 5.0, obstacle_color)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if obstacle_polygon.size() < 3:
		warnings.append("Obstacle polygon needs at least 3 points to form a valid obstacle")
	
	return warnings
