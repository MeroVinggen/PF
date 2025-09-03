@tool
extends Node2D
class_name PathfinderObstacle

signal static_state_changed(is_now_static: bool)
signal obstacle_changed()

@export var obstacle_polygon: PackedVector2Array = PackedVector2Array([
	Vector2(-25, -25),
	Vector2(25, -25),
	Vector2(25, 25),
	Vector2(-25, 25)
])

@export var is_static: bool = true : set = _set_is_static

var system: PathfinderSystem
var last_position: Vector2
var last_polygon: PackedVector2Array
var last_transform: Transform2D

func _set_is_static(value: bool):
	if is_static != value:
		is_static = value
		static_state_changed.emit(is_static)

func _has_changed() -> bool:
	# More sensitive change detection for better responsiveness
	var pos_threshold = 0.3 if not is_static else 0.8  # Tighter for dynamic
	var rot_threshold = 0.003 if not is_static else 0.008
	
	var pos_changed = last_position.distance_to(global_position) > pos_threshold
	var poly_changed = obstacle_polygon.size() != last_polygon.size()
	
	if not poly_changed:
		var threshold = 0.05  # More sensitive polygon change detection
		for i in obstacle_polygon.size():
			if obstacle_polygon[i].distance_to(last_polygon[i]) > threshold:
				poly_changed = true
				break
	
	var transform_changed = false
	if not _transforms_roughly_equal(last_transform, global_transform):
		transform_changed = true
	
	return pos_changed or poly_changed or transform_changed

func _transforms_roughly_equal(a: Transform2D, b: Transform2D) -> bool:
	var pos_threshold = 0.3 if not is_static else 0.8  # Tighter for dynamic
	var rot_threshold = 0.003 if not is_static else 0.008
	
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
		print("=== OBSTACLE CHANGE DETECTED ===")
		print("Obstacle at: ", global_position, " (was: ", last_position, ")")
		print("Transform changed: ", not _transforms_roughly_equal(last_transform, global_transform))
		_store_last_state()
		obstacle_changed.emit()
		if system:
			system._on_obstacle_changed()
		print("=== END OBSTACLE CHANGE ===")

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
	return PathfindingUtils.is_point_in_polygon(local_point, obstacle_polygon)

func _get_configuration_warnings() -> PackedStringArray:
	return PathfindingValidator.validate_pathfinder_obstacle(self)
