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

# Transform caching (like reference plugin)
var _transform_to_screen: Transform2D
var _transform_to_local: Transform2D

# Interaction state
var _active_vertex_index: int = -1
var _can_add_at: int = -1
var _is_dragging: bool = false
var _drag_start_pos: Vector2
var _cursor_pos: Vector2

func setup(plugin: EditorPlugin):
	_plugin = plugin
	_polygon_data = PolygonData.new()

func cleanup():
	clear_current()
	_polygon_data = null
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
		
		# Force editor selection
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(object)
	
	_request_overlay_update()

func clear_current():
	_current_object = null
	_current_property = ""
	if _polygon_data:
		_polygon_data.clear()
	_active_vertex_index = -1
	_can_add_at = -1
	_is_dragging = false
	_request_overlay_update()

func handles(object) -> bool:
	return _current_object != null and object == _current_object

func edit(object):
	# Handled by set_current
	pass

func draw_overlay(overlay: Control):
	if not _is_editing_valid():
		return
	
	_update_transforms()
	
	if _polygon_data.vertices.is_empty():
		return
	
	# FIXED: Draw polygon in world coordinates, just like reference plugin
	overlay.draw_colored_polygon(_transform_to_screen * _polygon_data.vertices, POLYGON_COLOR)
	
	# Draw vertices
	for i in range(_polygon_data.vertices.size()):
		var screen_pos = _transform_to_screen * _polygon_data.vertices[i]
		_draw_vertex(overlay, screen_pos, i)
	
	# Draw ghost vertex for adding
	if _can_add_at != -1:
		_draw_ghost_vertex(overlay, _cursor_pos)

func handle_input(event) -> bool:
	if not _is_editing_valid():
		return false
	
	var handled := false
	
	if event is InputEventMouseButton:
		handled = _handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		handled = _handle_mouse_motion(event)
	
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

func _update_transforms():
	if not _is_editing_valid():
		return
	
	var node = _current_object as Node2D
	# EXACTLY like reference plugin
	var transform_viewport = node.get_viewport_transform()
	var transform_canvas = node.get_canvas_transform()
	var transform_local = node.transform
	_transform_to_screen = transform_viewport * transform_canvas * transform_local
	_transform_to_local = _transform_to_screen.affine_inverse()

func _handle_mouse_motion(event: InputEventMouseMotion) -> bool:
	_cursor_pos = event.position
	
	if _is_dragging:
		_drag_vertex(_transform_to_local * event.position)
		return true
	else:
		# Update hover states
		var old_active = _active_vertex_index
		var old_add = _can_add_at
		
		_active_vertex_index = _get_active_vertex()
		_can_add_at = _get_active_side() if _active_vertex_index == -1 else -1
		
		return old_active != _active_vertex_index or old_add != _can_add_at
	
	return false

func _handle_mouse_button(event: InputEventMouseButton) -> bool:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _can_add_at != -1:
				_add_vertex()
				return true
			if _active_vertex_index != -1:
				_is_dragging = true
				_drag_start_pos = _polygon_data.vertices[_active_vertex_index]
				return true
		elif event.is_released() and _active_vertex_index != -1:
			_end_drag()
			return true
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_remove_vertex()
		return true
	
	return false

func _get_active_vertex() -> int:
	for i in range(_polygon_data.vertices.size()):
		var screen_pos = _transform_to_screen * _polygon_data.vertices[i]
		if (_cursor_pos - screen_pos).length() < CURSOR_THRESHOLD:
			return i
	return -1

func _get_active_side() -> int:
	if _active_vertex_index != -1:
		return -1
	
	var size = _polygon_data.vertices.size()
	for i in range(size):
		var a = _transform_to_screen * _polygon_data.vertices[i]
		var b = _transform_to_screen * _polygon_data.vertices[(i + 1) % size]
		
		var ab = (b - a).length()
		var ac = (_cursor_pos - a).length()
		var bc = (_cursor_pos - b).length()
		
		if (ac + bc) - ab < CURSOR_THRESHOLD:
			# Check height of triangle (distance from cursor to line)
			var s = (ab + ac + bc) * 0.5
			var area = sqrt(s * (s - ab) * (s - ac) * (s - bc))
			var height = 2.0 * area / ab if ab > 0 else 999.0
			
			if height < CURSOR_THRESHOLD:
				return (i + 1) % size
	return -1

func _add_vertex():
	var position = _transform_to_local * _cursor_pos
	var index = _can_add_at
	
	var undo = _plugin.get_undo_redo()
	undo.create_action("Add vertex")
	undo.add_do_method(self, "_do_add_vertex", index, position)
	undo.add_undo_method(self, "_do_remove_vertex", index)
	undo.commit_action()
	
	_can_add_at = -1

func _remove_vertex():
	if _active_vertex_index == -1 or _polygon_data.vertices.size() <= 3:
		return
	
	var index = _active_vertex_index
	var vertex_backup = _polygon_data.vertices[index]
	
	var undo = _plugin.get_undo_redo()
	undo.create_action("Remove vertex")
	undo.add_do_method(self, "_do_remove_vertex", index)
	undo.add_undo_method(self, "_do_add_vertex", index, vertex_backup)
	undo.commit_action()

func _drag_vertex(position: Vector2):
	if _active_vertex_index == -1:
		return
	_do_update_vertex(_active_vertex_index, position.round())

func _end_drag():
	if not _is_dragging:
		return
	
	var final_pos = (_transform_to_local * _cursor_pos).round()
	if final_pos != _drag_start_pos:
		var undo = _plugin.get_undo_redo()
		undo.create_action("Drag vertex")
		undo.add_do_method(self, "_do_update_vertex", _active_vertex_index, final_pos)
		undo.add_undo_method(self, "_do_update_vertex", _active_vertex_index, _drag_start_pos)
		undo.commit_action()
	
	_is_dragging = false

func _do_add_vertex(index: int, vertex: Vector2):
	_polygon_data.insert_vertex(index, vertex)
	_current_object.set(_current_property, _polygon_data.vertices)
	_active_vertex_index = index

func _do_remove_vertex(index: int):
	_polygon_data.remove_vertex(index)
	_current_object.set(_current_property, _polygon_data.vertices)
	_active_vertex_index = -1

func _do_update_vertex(index: int, vertex: Vector2):
	_polygon_data.set_vertex(index, vertex)
	_current_object.set(_current_property, _polygon_data.vertices)

func _draw_vertex(overlay: Control, position: Vector2, index: int):
	overlay.draw_circle(position, VERTEX_RADIUS, VERTEX_COLOR)
	if index == _active_vertex_index:
		overlay.draw_circle(position, VERTEX_RADIUS - 1.0, VERTEX_ACTIVE_COLOR)
		overlay.draw_string(overlay.get_theme_font("font"), 
			position + Vector2(-16.0, -16.0), str(index), HORIZONTAL_ALIGNMENT_LEFT, 32.0)

func _draw_ghost_vertex(overlay: Control, position: Vector2):
	overlay.draw_circle(position, VERTEX_RADIUS, VERTEX_NEW_COLOR)

func _request_overlay_update():
	if _plugin:
		_plugin.update_overlays()

# Helper class for polygon data management
class PolygonData:
	var vertices: PackedVector2Array = PackedVector2Array()
	
	func set_from_object(object: Object, property: String):
		vertices = object.get(property)
		if vertices.is_empty():
			_init_default_polygon(object, property)
	
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
