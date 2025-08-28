@tool
class_name PolygonEditor
extends RefCounted

# Visual constants
const CURSOR_THRESHOLD := 6.0
const VERTEX_RADIUS := 6.0
const VERTEX_EXCLUSION_RADIUS := 20.0  # 2x vertex radius - no ghost hints near existing vertices
const VERTEX_COLOR := Color(0.0, 0.5, 1.0, 0.5)
const VERTEX_ACTIVE_COLOR := Color(1.0, 1.0, 1.0)
const VERTEX_NEW_COLOR := Color(0.0, 1.0, 1.0, 0.5)
const POLYGON_COLOR := Color(0.0, 0.5, 1.0, 0.2)

# Core state
var _plugin: EditorPlugin
var _current_object: Object
var _current_property: String
var _polygon_data: PolygonData

# Track active property editor for proper cleanup
var _current_property_editor: Vector2ArrayPropertyEditor

# Transform caching (like reference plugin)
var _transform_to_screen: Transform2D
var _transform_to_local: Transform2D

# Interaction state
var _active_vertex_index: int = -1
var _can_add_at: int = -1
var _is_dragging: bool = false
var _drag_start_pos: Vector2
var _cursor_pos: Vector2

# NEW: Ghost vertex positioning
var _ghost_vertex_pos: Vector2

# Two-way sync: Track external changes
var _sync_timer: Timer
var _last_sync_check: PackedVector2Array = PackedVector2Array()

# NEW: Focus tracking
var _focus_check_timer: Timer
var _last_selected_nodes: Array[Node] = []

func setup(plugin: EditorPlugin):
	_plugin = plugin
	_polygon_data = PolygonData.new()
	
	# Setup sync monitoring timer
	_sync_timer = Timer.new()
	_sync_timer.wait_time = 0.05  # Check 20 times per second when editing
	_sync_timer.autostart = false
	_sync_timer.timeout.connect(_check_for_external_sync)
	
	# Setup focus tracking timer
	#_focus_check_timer = Timer.new()
	#_focus_check_timer.wait_time = 0.1  # Check 10 times per second
	#_focus_check_timer.autostart = true
	#_focus_check_timer.timeout.connect(_check_selection_focus)
	
	# Add timers to plugin so they get cleaned up properly
	_plugin.add_child(_sync_timer)
	#_plugin.add_child(_focus_check_timer)

func cleanup():
	print("cleanup")
	if _sync_timer and _sync_timer.is_inside_tree():
		_sync_timer.queue_free()
		_sync_timer = null
	
	if _focus_check_timer and _focus_check_timer.is_inside_tree():
		_focus_check_timer.queue_free()
		_focus_check_timer = null
	
	clear_current()
	_polygon_data = null
	_plugin = null

#func _check_selection_focus():
	#print("_check_selection_focus")
	#if not _is_editing_valid():
		#return
	#
	#var selection = EditorInterface.get_selection()
	#var selected_nodes = selection.get_selected_nodes()
	#
	## Check if our current object is still selected
	#var our_object_selected = false
	#for node in selected_nodes:
		#if node == _current_object:
			#our_object_selected = true
			#break
	#
	## If our object is no longer selected, stop editing
	#if not our_object_selected:
		#print("PolygonEditor: Node lost focus, stopping editing")
		#clear_current()
		#return
	#
	## Update last selected nodes for comparison
	#_last_selected_nodes = selected_nodes.duplicate()

func _check_for_external_sync():
	if not _is_editing_valid():
		return
	
	var current_array: PackedVector2Array = _current_object.get(_current_property)
	
	# Check if the array changed externally
	if not _arrays_equal(current_array, _last_sync_check):
		print("PolygonEditor detected external change")
		
		# If array is too small, we should stop editing
		if current_array.size() < 3:
			print("Array reduced below 3 points - clearing current editing")
			clear_current()
			return
		
		# Update our data and refresh display
		_polygon_data.vertices = current_array.duplicate()
		_last_sync_check = current_array.duplicate()
		_request_overlay_update()

func _arrays_equal(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	
	return true

func set_current(object: Object, property: String, property_editor: Vector2ArrayPropertyEditor = null):
	print("set_current")
	print("Setting current: ", object, " property: ", property)
	
	# If we're switching to a different property editor, notify the old one to stop
	if _current_property_editor and _current_property_editor != property_editor and is_instance_valid(_current_property_editor):
		print("Notifying previous property editor to stop editing")
		_current_property_editor.notify_stop_editing()
	
	# Clear previous state
	clear_current()
	
	# Set new state
	_current_object = object
	_current_property = property
	_current_property_editor = property_editor
	
	if object and property and object is CanvasItem:
		_polygon_data.set_from_object(object, property)
		
		# Initialize sync tracking
		_last_sync_check = _polygon_data.vertices.duplicate()
		
		# Start sync monitoring
		if _sync_timer:
			_sync_timer.start()
		
		# Force editor selection - this ensures focus
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(object)
		
		# Initialize focus tracking
		var selection = EditorInterface.get_selection()
		_last_selected_nodes = selection.get_selected_nodes().duplicate()
	
	_request_overlay_update()

func clear_current():
	print("clear_current")
	# Stop sync monitoring
	if _sync_timer:
		_sync_timer.stop()
	
	# Notify property editor that we're stopping
	if _current_property_editor and is_instance_valid(_current_property_editor):
		_current_property_editor.notify_stop_editing()
	
	_current_object = null
	_current_property = ""
	_current_property_editor = null
	if _polygon_data:
		_polygon_data.clear()
	_active_vertex_index = -1
	_can_add_at = -1
	_is_dragging = false
	_last_sync_check.clear()
	_last_selected_nodes.clear()
	_request_overlay_update()

func handles(object) -> bool:
	print("handles: ", _current_object)
	print("handles: ", _current_object != null and object == _current_object)
	return _current_object != null and object == _current_object

func edit(object):
	# Handled by set_current
	pass

func draw_overlay(overlay: Control):
	print("draw_overlay")
	# CRITICAL: Only draw if we have a valid current object and it's still selected
	if not _is_editing_valid():
		return
	
	# Double-check that our object is still selected
	var selection = EditorInterface.get_selection()
	var selected_nodes = selection.get_selected_nodes()
	var our_object_selected = false
	for node in selected_nodes:
		if node == _current_object:
			our_object_selected = true
			break
	
	if not our_object_selected:
		# Object is no longer selected, don't draw anything
		return
	
	_update_transforms()
	
	if _polygon_data.vertices.is_empty():
		return
	
	# Only draw polygon if we have at least 3 vertices
	if _polygon_data.vertices.size() >= 3:
		overlay.draw_colored_polygon(_transform_to_screen * _polygon_data.vertices, POLYGON_COLOR)
	
	# Draw vertices
	for i in range(_polygon_data.vertices.size()):
		var screen_pos = _transform_to_screen * _polygon_data.vertices[i]
		_draw_vertex(overlay, screen_pos, i)
	
	# Only show ghost vertex for adding if we have enough vertices to form a polygon
	if _can_add_at != -1 and _polygon_data.vertices.size() >= 3:
		_draw_ghost_vertex(overlay, _ghost_vertex_pos)

func handle_input(event) -> bool:
	if not _is_editing_valid():
		return false
	
	# Also check selection in input handling
	var selection = EditorInterface.get_selection()
	var selected_nodes = selection.get_selected_nodes()
	var our_object_selected = false
	for node in selected_nodes:
		if node == _current_object:
			our_object_selected = true
			break
	
	if not our_object_selected:
		# Object is no longer selected, don't handle input
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
	if not _current_object is CanvasItem:
		return false
	return true

func _update_transforms():
	if not _is_editing_valid():
		return
	
	var node = _current_object as CanvasItem
	var transform_viewport = node.get_viewport_transform()
	var transform_canvas = node.get_canvas_transform()
	
	# Handle different node types for local transform
	var transform_local: Transform2D
	if node is Node2D:
		# Node2D nodes have a transform property
		transform_local = (node as Node2D).transform
	elif node is Control:
		# Control nodes use position, rotation, scale, and pivot_offset
		var control = node as Control
		transform_local = Transform2D()
		
		# Apply scale
		transform_local = transform_local.scaled(control.scale)
		
		# Apply rotation
		if control.rotation != 0.0:
			transform_local = transform_local.rotated(control.rotation)
		
		# Apply translation (position - pivot_offset, then add pivot_offset back)
		var pivot = control.pivot_offset
		transform_local.origin = control.position + pivot
		if pivot != Vector2.ZERO:
			# Rotate and scale the pivot offset, then subtract it
			var transformed_pivot = transform_local.basis_xform(pivot)
			transform_local.origin -= transformed_pivot
	else:
		# Fallback for other CanvasItem types
		transform_local = Transform2D()
	
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
		var old_ghost_pos = _ghost_vertex_pos
		
		_active_vertex_index = _get_active_vertex()
		
		# Only show ghost vertex if we have at least 3 vertices (can form a polygon)
		if _active_vertex_index == -1 and _polygon_data.vertices.size() >= 3:
			var add_result = _get_active_side_optimized()
			_can_add_at = add_result.index
			_ghost_vertex_pos = add_result.position
		else:
			_can_add_at = -1
		
		# Return true if ANY of these changed (including ghost position)
		return (old_active != _active_vertex_index or 
				old_add != _can_add_at or 
				old_ghost_pos != _ghost_vertex_pos)
	
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

# OPTIMIZED: More responsive ghost vertex positioning with exclusion zones
func _get_active_side_optimized() -> Dictionary:
	var result = {"index": -1, "position": Vector2.ZERO}
	
	if _active_vertex_index != -1:
		return result
	
	var size = _polygon_data.vertices.size()
	if size < 3:  # Need at least 3 vertices to form sides
		return result
		
	var min_distance = CURSOR_THRESHOLD
	var best_index = -1
	var best_position = Vector2.ZERO
	
	for i in range(size):
		var a = _transform_to_screen * _polygon_data.vertices[i]
		var b = _transform_to_screen * _polygon_data.vertices[(i + 1) % size]
		
		# Find closest point on line segment to cursor
		var closest_point = _get_closest_point_on_segment(a, b, _cursor_pos)
		var distance = (_cursor_pos - closest_point).length()
		
		if distance < min_distance:
			# NEW: Check if ghost vertex would be too close to existing vertices
			var too_close_to_vertex = false
			for j in range(size):
				var vertex_screen = _transform_to_screen * _polygon_data.vertices[j]
				if (closest_point - vertex_screen).length() < VERTEX_EXCLUSION_RADIUS:
					too_close_to_vertex = true
					break
			
			if not too_close_to_vertex:
				min_distance = distance
				best_index = (i + 1) % size
				best_position = closest_point
	
	if best_index != -1:
		result.index = best_index
		result.position = best_position
	
	return result

# Helper function to find closest point on line segment
func _get_closest_point_on_segment(a: Vector2, b: Vector2, point: Vector2) -> Vector2:
	var ab = b - a
	var ap = point - a
	
	# If segment has zero length, return point a
	if ab.length_squared() == 0:
		return a
	
	# Project point onto line, clamped to segment
	var t = ap.dot(ab) / ab.length_squared()
	t = clamp(t, 0.0, 1.0)
	
	return a + t * ab

func _add_vertex():
	# Use the world position calculated from ghost vertex
	var position = _transform_to_local * _ghost_vertex_pos
	var index = _can_add_at
	
	var undo = _plugin.get_undo_redo()
	undo.create_action("Add vertex")
	undo.add_do_method(self, "_do_add_vertex", index, position)
	undo.add_undo_method(self, "_do_remove_vertex", index)
	undo.commit_action()
	
	_can_add_at = -1

func _remove_vertex():
	# Can only remove vertices if we have more than 3 (to maintain polygon)
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
	
	# Update sync tracking
	_last_sync_check = _polygon_data.vertices.duplicate()

func _do_remove_vertex(index: int):
	_polygon_data.remove_vertex(index)
	_current_object.set(_current_property, _polygon_data.vertices)
	_active_vertex_index = -1
	
	# Update sync tracking
	_last_sync_check = _polygon_data.vertices.duplicate()
	
	# Check if we should stop editing due to insufficient points
	if _polygon_data.vertices.size() < 3:
		print("Polygon reduced to less than 3 vertices - clearing current editing")
		call_deferred("clear_current")  # Defer to avoid issues during undo/redo

func _do_update_vertex(index: int, vertex: Vector2):
	_polygon_data.set_vertex(index, vertex)
	_current_object.set(_current_property, _polygon_data.vertices)
	
	# Update sync tracking
	_last_sync_check = _polygon_data.vertices.duplicate()

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
		# Remove the auto-initialization - let the property editor handle this
	
	func clear():
		vertices = PackedVector2Array()
	
	func insert_vertex(index: int, vertex: Vector2):
		vertices.insert(index, vertex)
	
	func remove_vertex(index: int):
		vertices.remove_at(index)
	
	func set_vertex(index: int, vertex: Vector2):
		vertices[index] = vertex
