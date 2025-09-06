@tool
extends Node2D
class_name PathfinderObstacle

signal static_state_changed(obstacle: PathfinderObstacle)
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

var pos_threshold: float
var rot_threshold: float

func _set_is_static(value: bool):
	if is_static != value:
		is_static = value
		static_state_changed.emit(self)


func _has_changed() -> bool:
	# pos chenged
	if last_position.distance_to(global_position) > pos_threshold:
		return true
	
	# polygon changed by size
	if obstacle_polygon.size() != last_polygon.size():
		return true
	# polygon changed by vertex
	else: 
		for i in obstacle_polygon.size():
			if obstacle_polygon[i].distance_to(last_polygon[i]) > PathfindingConstants.POLYGON_CHANGE_THRESHOLD:
				return true
	
	# transform changed
	if not _transforms_roughly_equal(last_transform, global_transform):
		return true
	
	return false

func _transforms_roughly_equal(a: Transform2D, b: Transform2D) -> bool:
	return (a.origin.distance_to(b.origin) < pos_threshold and 
			abs(a.get_rotation() - b.get_rotation()) < rot_threshold and
			(a.get_scale() - b.get_scale()).length() < PathfindingConstants.TRANSFORM_SCALE_THRESHOLD)

func _exit_tree():
	if system:
		system.unregister_obstacle(self)

func _physics_process(delta):
	if Engine.is_editor_hint() or is_static:
		return
	
	_check_for_changes()


func _check_for_changes():
	if _has_changed():
		print("Obstacle at: ", global_position, " (was: ", last_position, ")")
		_store_last_state()
		obstacle_changed.emit()
		last_position = global_position  # Update position for next frame

func _store_last_state():
	"""Store current state for change detection"""
	# Don't update last_position immediately, let it be updated next frame
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
