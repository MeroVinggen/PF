@tool
extends EditorPlugin

## Distance in pixels from cursor to polygon vertex when it will become active (hovered)
const CURSOR_THRESHOLD := 6.0

## Radius of vertex
const VERTEX_RADIUS := 6.0

## Color of the vertex
const VERTEX_COLOR := Color(0.0, 0.5, 1.0, 0.5)

## Color of the active (hovered) vertex
const VERTEX_ACTIVE_COLOR := Color(1.0, 1.0, 1.0)

## Color of the virtual vertex on the polygon sides when it's hovered.
## At this place new vertex will be created
const VERTEX_NEW_COLOR := Color(0.0, 1.0, 1.0, 0.5)

## Color of the polygon
const POLYGON_COLOR := Color(0.0, 0.5, 1.0, 0.2)

var _current_object: Object
var _current_property: String
var _current_polygon: PackedVector2Array
var _transform_to_view: Transform2D
var _transform_to_base: Transform2D
var _is_dragging := false
var _drag_started := false
var _drag_ended := false
var _drag_from: Vector2
var _drag_to: Vector2
var _can_add_at: int = -1
var _cursor: Vector2
var _active_index: int = -1

var _inspector_plugin: EditorInspectorPlugin

func _enter_tree():
	print("Vector2Array plugin entering tree")
	_inspector_plugin = Vector2ArrayInspectorPlugin.new()
	_inspector_plugin.editor_plugin = self
	add_inspector_plugin(_inspector_plugin)
	print("Inspector plugin added")

func _exit_tree():
	print("Vector2Array plugin exiting tree")
	remove_inspector_plugin(_inspector_plugin)
	_clear_current()

func set_current_vector2array(object: Object, property: String):
	print("Setting current vector2array: ", object, " property: ", property)
	_current_object = object
	_current_property = property
	if object and property and object is Node2D:
		_current_polygon = object.get(property)
		print("Current polygon: ", _current_polygon)
		_init_polygon_if_empty()
		# Force editor selection to trigger our handlers
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(object)
	else:
		_current_polygon = PackedVector2Array()
		# Clear the selection when stopping edit
		if _current_object:
			EditorInterface.get_selection().clear()
	_active_index = -1
	update_overlays()
	print("Overlays updated")

func _init_polygon_if_empty():
	if _current_polygon.is_empty() and _current_object and _current_property:
		_current_polygon = PackedVector2Array([Vector2(32.0, 0.0), Vector2(-32.0, 32.0), Vector2(-32.0, -32.0)])
		_current_object.set(_current_property, _current_polygon)

func _clear_current():
	_current_object = null
	_current_property = ""
	_current_polygon = PackedVector2Array()
	_active_index = -1
	_is_dragging = false
	_drag_started = false
	_drag_ended = false
	_can_add_at = -1
	update_overlays()

func _has_main_screen():
	return false

func _handles(object):
	var should_handle = _current_object != null and object == _current_object
	return should_handle

func _edit(object):
	# Only accept edit if we're currently editing this object
	pass

func _forward_canvas_draw_over_viewport(overlay: Control):
	if not _current_object or not _current_property or not _current_object is Node2D:
		return
	_sync_polygon_from_object()
	_update_transforms()
	_draw_polygon(overlay)

func _forward_canvas_gui_input(event):
	if not _current_object or not _current_property or not _current_object is Node2D:
		return false
	_sync_polygon_from_object()
	var handled := _handle_left_click(event)\
		or _handle_right_click(event)\
		or _handle_mouse_move(event)
	if handled: 
		update_overlays()
	return handled

func _handle_left_click(event) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			if _can_add_at != -1:
				_add_vertex()
			if _active_index != -1:
				_drag_started = true
				_is_dragging = true
		if event.is_released() and _active_index != -1:
			_drag_ended = true
			_is_dragging = false
		return true
	return false

func _handle_right_click(event) -> bool:
	if event is InputEventMouseButton\
			and event.button_index == MOUSE_BUTTON_RIGHT\
			and event.is_pressed():
		_remove_vertex()
		return true
	return false

func _handle_mouse_move(event) -> bool:
	if event is InputEventMouseMotion:
		var old_active = _active_index
		var old_can_add = _can_add_at
		
		_cursor = event.position
		
		if _is_dragging or _drag_ended:
			_drag_vertex(_transform_to_base * event.position)
			return true
		else:
			_active_index = _get_active_vertex()
			_can_add_at = _get_active_side()
			# Only update overlays if something actually changed
			return _active_index != old_active or _can_add_at != old_can_add
	return false

func _get_active_vertex() -> int:
	for index in range(0, _current_polygon.size()):
		var screen_vertex = _transform_to_view * _current_polygon[index]
		if (_cursor - screen_vertex).length() < CURSOR_THRESHOLD:
			return index
	return -1

func _get_active_side() -> int:
	if _active_index != -1:
		return -1
		
	var size := _current_polygon.size()
	for index in range(0, size):
		var a := _transform_to_view * _current_polygon[index]
		var b := _transform_to_view * _current_polygon[index + 1 if index + 1 < size else 0]
		var ab = (b - a).length()
		var ac = (_cursor - a).length()
		var bc = (_cursor - b).length()
		if (ac + bc) - ab < CURSOR_THRESHOLD:
			var s: float = (ab + ac + bc) * 0.5
			var A: float = sqrt(s * (s - ab) * (s - ac) * (s - bc))
			var h: float = 2.0 * A / ab
			if h < CURSOR_THRESHOLD:
				return index + 1
	return -1

func _add_vertex():
	var position: Vector2 = _transform_to_base * _cursor
	var undo := get_undo_redo()
	undo.create_action("Add vertex")
	undo.add_do_method(self, "_do_add_vertex", _can_add_at, position)
	undo.add_undo_method(self, "_do_remove_vertex", _can_add_at)
	undo.commit_action()
	_can_add_at = -1
	_drag_to = position

func _do_add_vertex(index: int, vertex: Vector2):
	_current_polygon.insert(index, vertex)
	_current_object.set(_current_property, _current_polygon)
	_active_index = index

func _remove_vertex():
	if _active_index == -1 or _current_polygon.size() < 4:
		return
	var vertex_backup = _current_polygon[_active_index]
	var undo := get_undo_redo()
	undo.create_action("Remove vertex")
	undo.add_do_method(self, "_do_remove_vertex", _active_index)
	undo.add_undo_method(self, "_do_add_vertex", _active_index, vertex_backup)
	undo.commit_action()

func _do_remove_vertex(index: int):
	_current_polygon.remove_at(index)
	_current_object.set(_current_property, _current_polygon)
	_active_index = -1

func _drag_vertex(position: Vector2):
	if _active_index == -1:
		return
	_drag_to = _drag_to if _drag_ended else position.round()
	if _drag_started:
		_drag_from = _current_polygon[_active_index]
		_drag_started = false
	if _drag_ended:
		if _drag_to != _drag_from:
			var undo := get_undo_redo()
			undo.create_action("Drag vertex")
			undo.add_do_method(self, "_do_update_vertex", _active_index, _drag_to)
			undo.add_undo_method(self, "_do_update_vertex", _active_index, _drag_from)
			undo.commit_action()
		_drag_ended = false
	_do_update_vertex(_active_index, _drag_to)

func _do_update_vertex(index: int, vertex: Vector2):
	_current_polygon[index] = vertex
	_current_object.set(_current_property, _current_polygon)

func _sync_polygon_from_object():
	if _current_object and _current_property:
		_current_polygon = _current_object.get(_current_property)

func _update_transforms():
	var node: Node2D = _current_object as Node2D
	if not node:
		return
	
	# Get the proper canvas transform that includes zoom and pan
	var canvas_transform = node.get_canvas_transform()
	var global_transform = node.global_transform
	
	# Combine transforms: local polygon -> global -> screen
	_transform_to_view = canvas_transform * global_transform
	_transform_to_base = _transform_to_view.affine_inverse()

func _draw_polygon(overlay: Control):
	if _current_polygon.is_empty():
		return
	
	# Transform polygon to screen coordinates
	var screen_polygon = _transform_to_view * _current_polygon
	overlay.draw_colored_polygon(screen_polygon, POLYGON_COLOR)
	
	for index in range(_current_polygon.size()):
		var screen_pos = _transform_to_view * _current_polygon[index]
		_draw_vertex(overlay, screen_pos, index)
	
	if _can_add_at != -1:
		_draw_ghost_vertex(overlay, _cursor)

func _draw_vertex(overlay: Control, position: Vector2, index: int):
	overlay.draw_circle(position, VERTEX_RADIUS, VERTEX_COLOR)
	overlay.draw_circle(position, VERTEX_RADIUS - 1.0,\
		VERTEX_ACTIVE_COLOR if index == _active_index else Color(0,0,0,0))
	if index == _active_index:
		overlay.draw_string(overlay.get_theme_font("font"),\
			position + Vector2(-16.0, -16.0), str(index), 1, 32.0)

func _draw_ghost_vertex(overlay: Control, position: Vector2):
	overlay.draw_circle(position, VERTEX_RADIUS, VERTEX_NEW_COLOR)

# Inspector plugin to detect PackedVector2Array selection
class Vector2ArrayInspectorPlugin extends EditorInspectorPlugin:
	var editor_plugin: EditorPlugin
	
	func _can_handle(object):
		return true
	
	func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool):
		if type == TYPE_PACKED_VECTOR2_ARRAY:
			print("Found PackedVector2Array property: ", name)
			var property_editor = Vector2ArrayPropertyEditor.new()
			property_editor.setup(editor_plugin, object, name)
			add_custom_control(property_editor)  # Add as custom control instead of replacing
			return false  # Don't replace the original property editor
		return false

# Property editor for PackedVector2Array
class Vector2ArrayPropertyEditor extends EditorProperty:
	var editor_plugin: EditorPlugin
	var target_object: Object
	var property_name: String
	var edit_button: Button
	var is_editing: bool = false
	
	func _exit_tree():
		if is_editing:
			_stop_editing()
	
	func setup(plugin: EditorPlugin, object: Object, prop_name: String):
		editor_plugin = plugin
		target_object = object
		property_name = prop_name
		
		edit_button = Button.new()
		edit_button.text = "Edit in 2D View"
		edit_button.pressed.connect(_on_edit_pressed)
		add_child(edit_button)
		
		_update_button_state()
	
	func _on_edit_pressed():
		if is_editing:
			_stop_editing()
		else:
			_start_editing()
	
	func _start_editing():
		is_editing = true
		editor_plugin.set_current_vector2array(target_object, property_name)
		edit_button.text = "Stop Editing"
		edit_button.modulate = Color.GREEN
		print("Started editing ", property_name, " on ", target_object.name, " with ", target_object.get(property_name).size(), " vertices")
	
	func _stop_editing():
		is_editing = false
		editor_plugin.set_current_vector2array(null, "")
		edit_button.text = "Edit in 2D View"
		edit_button.modulate = Color.WHITE
	
	func _update_button_state():
		if target_object and target_object is Node2D:
			edit_button.disabled = false
			edit_button.tooltip_text = "Click to edit this PackedVector2Array as a polygon in the 2D view"
		else:
			edit_button.disabled = true
			edit_button.tooltip_text = "This feature only works with Node2D objects"
