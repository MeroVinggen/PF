@tool
extends Node2D
class_name PathfinderObstacle

@export var obstacle_polygon: PackedVector2Array = PackedVector2Array([
	Vector2(-25, -25),
	Vector2(25, -25),
	Vector2(25, 25),
	Vector2(-25, 25)
])

@export var is_static: bool = true
@export var debug_draw: bool = true
@export var obstacle_color: Color = Color.RED

var system: PathfinderSystem
var last_position: Vector2
var last_polygon: PackedVector2Array
var last_transform: Transform2D

signal obstacle_changed()

func _has_changed() -> bool:
	var pos_changed = last_position.distance_to(global_position) > 0.5
	var poly_changed = obstacle_polygon.size() != last_polygon.size()
	if not poly_changed:
		var threshold = 0.1
		for i in obstacle_polygon.size():
			if obstacle_polygon[i].distance_to(last_polygon[i]) > threshold:
				poly_changed = true
				break
	
	var transform_changed = false
	if not _transforms_roughly_equal(last_transform, global_transform):
		transform_changed = true
	
	return pos_changed or poly_changed or transform_changed

func _transforms_roughly_equal(a: Transform2D, b: Transform2D) -> bool:
	var pos_threshold = 0.5 if not is_static else 1.0
	var rot_threshold = 0.005 if not is_static else 0.01
	
	return (a.origin.distance_to(b.origin) < pos_threshold and 
			abs(a.get_rotation() - b.get_rotation()) < rot_threshold and
			(a.get_scale() - b.get_scale()).length() < 0.01)

func _exit_tree():
	if system and not Engine.is_editor_hint():
		system.unregister_obstacle(self)

func _physics_process(delta):
	if Engine.is_editor_hint() or is_static:
		return
	
	_check_for_changes()


func _check_for_changes():
	if _has_changed():
		_store_last_state()
		obstacle_changed.emit()
		if system:
			system._on_obstacle_changed()

func _store_last_state():
	"""Store current state for change detection"""
	last_position = global_position
	last_polygon = obstacle_polygon.duplicate()
	last_transform = global_transform


func get_world_polygon() -> PackedVector2Array:
	var world_poly: PackedVector2Array = []
	for point in obstacle_polygon:
		world_poly.append(global_transform * point)
	return world_poly

func is_point_inside(point: Vector2) -> bool:
	var local_point = global_transform.affine_inverse() * point
	return _is_point_in_polygon(local_point, obstacle_polygon)

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
		# Color coding: red for static, orange for dynamic
		var draw_color = obstacle_color
		if not is_static:
			draw_color = Color.ORANGE
		
		# Draw filled polygon
		draw_colored_polygon(obstacle_polygon, draw_color * 0.7)
		# Draw outline
		var outline = obstacle_polygon + PackedVector2Array([obstacle_polygon[0]])
		draw_polyline(outline, draw_color, 2.0)
		
		# Draw dynamic indicator
		if not is_static:
			draw_circle(Vector2.ZERO, 8.0, Color.YELLOW)
			draw_circle(Vector2.ZERO, 6.0, Color.ORANGE)
	else:
		# Draw as points if not enough vertices
		for point in obstacle_polygon:
			draw_circle(point, 5.0, obstacle_color)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if obstacle_polygon.size() < 3:
		warnings.append("Obstacle polygon needs at least 3 points to form a valid obstacle")
	
	if not is_static:
		warnings.append("Dynamic obstacles will impact performance - use sparingly")
	
	return warnings
