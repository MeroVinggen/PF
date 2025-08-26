@tool
class_name PolygonEditor
extends RefCounted

# Visual constants
const CURSOR_THRESHOLD := 6.0
const VERTEX_RADIUS := 6.0
const VERTEX_COLOR := Color(0.0, 0.5, 1.0, 0.5)
const VERTEX_ACTIVE_COLOR := Color(1.0, 1.0, 1.0)
const VERTEX_NEW_COLOR := Color(0.0, 1.0, 1.0, 0.5)
const POLYGON_COLOR := Color(0.0, 0.5, 1.0, 0.2)

# Core state
var _plugin: EditorPlugin
var _current_object: Object
var _current_property: String
var _polygon_data: PolygonData

# Performance caching
var _transforms: TransformCache
var _screen_cache: ScreenCache
var _interaction_cache: InteractionCache

# Dirty flags for performance
var _needs_transform_update := true
var _needs_screen_update := true
var _needs_interaction_update := true
var _needs_overlay_update := true

func setup(plugin: EditorPlugin):
	_plugin = plugin
	_polygon_data = PolygonData.new()
	_transforms = TransformCache.new()
	_screen_cache = ScreenCache.new()
	_interaction_cache = InteractionCache.new()

func cleanup():
	clear_current()
	_polygon_data = null
	_transforms = null
	_screen_cache = null
	_interaction_cache = null
	_plugin = null

func set_current(object: Object, property: String):
	print("Setting current: ", object, " property: ", property)
	
	# Clear previous state
	clear_current()
	
	# Set new state
	_current_object = object
	_current_property = property
	
	if object and property and object is Node2D:
		_polygon_data.set_from_object(object, property)
		_mark_all_dirty()
		
		# Force editor selection
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(object)
	
	_request_overlay_update()

func clear_current():
	_current_object = null
	_current_property = ""
	if _polygon_data:
		_polygon_data.clear()
	_clear_caches()
	_request_overlay_update()

func handles(object) -> bool:
	return _current_object != null and object == _current_object

func edit(object):
	# Handled by set_current
	pass

func draw_overlay(overlay: Control):
	if not _is_editing_valid():
		return
	
	_update_if_dirty()
	
	if _polygon_data.vertices.is_empty():
		return
	
	# FIXED: Draw in world/canvas space, not screen space like the original plugin
	# Transform polygon to screen coordinates for drawing
	var screen_polygon = _transforms.to_screen * _polygon_data.vertices
	overlay.draw_colored_polygon(screen_polygon, POLYGON_COLOR)
	
	# Draw vertices in screen space but maintain world positioning
	for i in range(_polygon_data.vertices.size()):
		var screen_pos = _transforms.to_screen * _polygon_data.vertices[i]
		_draw_vertex(overlay, screen_pos, i)
	
	# Draw ghost vertex for adding at cursor position
	if _interaction_cache.can_add_at != -1:
		_draw_ghost_vertex(overlay, _interaction_cache.cursor_pos)

func handle_input(event) -> bool:
	if not _is_editing_valid():
		return false
	
	var handled := false
	
	if event is InputEventMouseMotion:
		handled = _handle_mouse_motion(event)
	elif event is InputEventMouseButton:
		handled = _handle_mouse_button(event)
	
	if handled:
		_request_overlay_update()
	
	return handled

# Private methods
func _is_editing_valid() -> bool:
	if not _current_object or not _current_property:
		return false
	if not is_instance_valid(_current_object):
		clear_current()
		return false
	if not _current_object is Node2D:
		return false
	return true

func _update_if_dirty():
	if not _is_editing_valid():
		return
	
	# Sync polygon data from object
	_polygon_data.sync_from_object(_current_object, _current_property)
	
	# Update transforms if needed
	if _needs_transform_update:
		_transforms.update(_current_object as Node2D)
		_needs_transform_update = false
		_needs_screen_update = true
	
	# Update screen positions if needed
	if _needs_screen_update:
		_screen_cache.update(_polygon_data.vertices, _transforms)
		_needs_screen_update = false
		_needs_interaction_update = true
	
	# Update interaction cache if needed
	if _needs_interaction_update:
		_interaction_cache.update_hover_state(_screen_cache.vertex_positions, _polygon_data.vertices, _transforms)
		_needs_interaction_update = false

func _handle_mouse_motion(event: InputEventMouseMotion) -> bool:
	_interaction_cache.cursor_pos = event.position
	
	# FIXED: Handle dragging - using Transform2D multiplication instead of function call
	if _interaction_cache.is_dragging:
		_drag_vertex(_transforms.to_local * event.position)
		return true
	
	# Update hover states
	var old_active = _interaction_cache.active_vertex_index
	var old_add = _interaction_cache.can_add_at
	
	_interaction_cache.update_hover_state(_screen_cache.vertex_positions, _polygon_data.vertices, _transforms)
	
	# Only return true if something changed
	return old_active != _interaction_cache.active_vertex_index or old_add != _interaction_cache.can_add_at

func _handle_mouse_button(event: InputEventMouseButton) -> bool:
	if event.button_index == MOUSE_BUTTON_LEFT:
		return _handle_left_click(event)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		return _handle_right_click(event)
	return false

func _handle_left_click(event: InputEventMouseButton) -> bool:
	if event.pressed:
		if _interaction_cache.active_vertex_index != -1:
			_start_drag()
			return true
		elif _interaction_cache.can_add_at != -1:
			_add_vertex()
			return true
	elif _interaction_cache.is_dragging:
		_end_drag()
		return true
	return false

func _handle_right_click(event: InputEventMouseButton) -> bool:
	if event.pressed and _interaction_cache.active_vertex_index != -1:
		_remove_vertex()
		return true
	return false

func _start_drag():
	_interaction_cache.is_dragging = true
	_interaction_cache.drag_start_pos = _polygon_data.vertices[_interaction_cache.active_vertex_index]

func _end_drag():
	if not _interaction_cache.is_dragging:
		return
	
	# FIXED: Using Transform2D multiplication with parentheses for .round()
	var final_pos = (_transforms.to_local * _interaction_cache.cursor_pos).round()
	if final_pos != _interaction_cache.drag_start_pos:
		var undo = _plugin.get_undo_redo()
		undo.create_action("Drag vertex")
		undo.add_do_method(self, "_do_update_vertex", _interaction_cache.active_vertex_index, final_pos)
		undo.add_undo_method(self, "_do_update_vertex", _interaction_cache.active_vertex_index, _interaction_cache.drag_start_pos)
		undo.commit_action()
	
	_interaction_cache.is_dragging = false

func _drag_vertex(position: Vector2):
	if _interaction_cache.active_vertex_index == -1:
		return
	_do_update_vertex(_interaction_cache.active_vertex_index, position.round())

func _add_vertex():
	# FIXED: Using Transform2D multiplication instead of function call
	var position = _transforms.to_local * _interaction_cache.cursor_pos
	var index = _interaction_cache.can_add_at
	
	var undo = _plugin.get_undo_redo()
	undo.create_action("Add vertex")
	undo.add_do_method(self, "_do_add_vertex", index, position)
	undo.add_undo_method(self, "_do_remove_vertex", index)
	undo.commit_action()
	
	_interaction_cache.can_add_at = -1

func _remove_vertex():
	if _interaction_cache.active_vertex_index == -1 or _polygon_data.vertices.size() <= 3:
		return
	
	var index = _interaction_cache.active_vertex_index
	var vertex_backup = _polygon_data.vertices[index]
	
	var undo = _plugin.get_undo_redo()
	undo.create_action("Remove vertex")
	undo.add_do_method(self, "_do_remove_vertex", index)
	undo.add_undo_method(self, "_do_add_vertex", index, vertex_backup)
	undo.commit_action()

func _do_add_vertex(index: int, vertex: Vector2):
	_polygon_data.insert_vertex(index, vertex)
	_current_object.set(_current_property, _polygon_data.vertices)
	_interaction_cache.active_vertex_index = index
	_mark_geometry_dirty()

func _do_remove_vertex(index: int):
	_polygon_data.remove_vertex(index)
	_current_object.set(_current_property, _polygon_data.vertices)
	_interaction_cache.active_vertex_index = -1
	_mark_geometry_dirty()

func _do_update_vertex(index: int, vertex: Vector2):
	_polygon_data.set_vertex(index, vertex)
	_current_object.set(_current_property, _polygon_data.vertices)
	_mark_geometry_dirty()

func _draw_vertex(overlay: Control, position: Vector2, index: int):
	# Draw vertex circle at screen position (transformed from world space)
	overlay.draw_circle(position, VERTEX_RADIUS, VERTEX_COLOR)
	if index == _interaction_cache.active_vertex_index:
		# Draw active vertex highlight
		overlay.draw_circle(position, VERTEX_RADIUS - 1.0, VERTEX_ACTIVE_COLOR)
		# Draw vertex index label
		overlay.draw_string(overlay.get_theme_font("font"), 
			position + Vector2(-16.0, -16.0), str(index), HORIZONTAL_ALIGNMENT_LEFT, 32.0)

func _draw_ghost_vertex(overlay: Control, position: Vector2):
	# Draw ghost vertex at cursor position (already in screen space)
	overlay.draw_circle(position, VERTEX_RADIUS, VERTEX_NEW_COLOR)

func _mark_all_dirty():
	_needs_transform_update = true
	_needs_screen_update = true
	_needs_interaction_update = true

func _mark_geometry_dirty():
	_needs_screen_update = true
	_needs_interaction_update = true

func _clear_caches():
	if _screen_cache:
		_screen_cache.clear()
	if _interaction_cache:
		_interaction_cache.clear()
	_mark_all_dirty()

func _request_overlay_update():
	if _plugin:
		_plugin.update_overlays()

# Helper classes for organized data management
class PolygonData:
	var vertices: PackedVector2Array = PackedVector2Array()
	
	func set_from_object(object: Object, property: String):
		vertices = object.get(property)
		if vertices.is_empty():
			_init_default_polygon(object, property)
	
	func sync_from_object(object: Object, property: String):
		var new_vertices = object.get(property)
		if new_vertices != vertices:
			vertices = new_vertices
	
	func clear():
		vertices = PackedVector2Array()
	
	func insert_vertex(index: int, vertex: Vector2):
		vertices.insert(index, vertex)
	
	func remove_vertex(index: int):
		vertices.remove_at(index)
	
	func set_vertex(index: int, vertex: Vector2):
		vertices[index] = vertex
	
	func _init_default_polygon(object: Object, property: String):
		vertices = PackedVector2Array([
			Vector2(32.0, 0.0), Vector2(-32.0, 32.0), 
			Vector2(-32.0, -32.0), Vector2(32.0, -32.0)
		])
		object.set(property, vertices)

class TransformCache:
	var to_screen: Transform2D
	var to_local: Transform2D
	var _last_transform: Transform2D
	var _is_valid: bool = false
	
	func update(node: Node2D):
		var current_transform = _get_full_transform(node)
		if not _is_valid or current_transform != _last_transform:
			to_screen = current_transform
			to_local = current_transform.affine_inverse()
			_last_transform = current_transform
			_is_valid = true
	
	func _get_full_transform(node: Node2D) -> Transform2D:
		return node.get_viewport_transform() * node.get_canvas_transform() * node.transform

class ScreenCache:
	var screen_polygon: PackedVector2Array = PackedVector2Array()
	var vertex_positions: PackedVector2Array = PackedVector2Array()
	
	func update(vertices: PackedVector2Array, transforms: TransformCache):
		screen_polygon = transforms.to_screen * vertices
		vertex_positions = screen_polygon.duplicate()
	
	func clear():
		screen_polygon = PackedVector2Array()
		vertex_positions = PackedVector2Array()

class InteractionCache:
	var cursor_pos: Vector2
	var active_vertex_index: int = -1
	var can_add_at: int = -1
	var is_dragging: bool = false
	var drag_start_pos: Vector2
	
	func update_hover_state(screen_vertices: PackedVector2Array, world_vertices: PackedVector2Array, transforms: TransformCache):
		active_vertex_index = _find_active_vertex(screen_vertices)
		can_add_at = _find_add_position(screen_vertices, world_vertices, transforms) if active_vertex_index == -1 else -1
	
	func clear():
		active_vertex_index = -1
		can_add_at = -1
		is_dragging = false
		cursor_pos = Vector2.ZERO
		drag_start_pos = Vector2.ZERO
	
	func _find_active_vertex(screen_vertices: PackedVector2Array) -> int:
		for i in range(screen_vertices.size()):
			if (cursor_pos - screen_vertices[i]).length() < PolygonEditor.CURSOR_THRESHOLD:
				return i
		return -1
	
	func _find_add_position(screen_vertices: PackedVector2Array, world_vertices: PackedVector2Array, transforms: TransformCache) -> int:
		var size = screen_vertices.size()
		for i in range(size):
			var a = screen_vertices[i]
			var b = screen_vertices[(i + 1) % size]
			
			# Quick distance check to edge
			var ab_length = (b - a).length()
			var ac_length = (cursor_pos - a).length()
			var bc_length = (cursor_pos - b).length()
			
			if (ac_length + bc_length) - ab_length < PolygonEditor.CURSOR_THRESHOLD:
				# More precise distance to line check
				var s = (ab_length + ac_length + bc_length) * 0.5
				var area = sqrt(s * (s - ab_length) * (s - ac_length) * (s - bc_length))
				var height = 2.0 * area / ab_length if ab_length > 0 else 999
				
				if height < PolygonEditor.CURSOR_THRESHOLD:
					return (i + 1) % size
		return -1
