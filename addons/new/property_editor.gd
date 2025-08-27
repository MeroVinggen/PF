@tool
class_name Vector2ArrayPropertyEditor
extends EditorProperty

var _polygon_editor: PolygonEditor
var _target_object: Object
var _property_name: String
var _edit_button: Button
var _is_editing: bool = false

# Performance: Cache button states
var _last_button_state: bool = false
var _needs_button_update: bool = true

func _exit_tree():
	if _is_editing:
		_stop_editing()

func setup(polygon_editor: PolygonEditor, object: Object, prop_name: String):
	_polygon_editor = polygon_editor
	_target_object = object
	_property_name = prop_name
	
	_create_ui()
	_update_button_state()

func cleanup():
	if _is_editing:
		_stop_editing_without_editor_call()
	_polygon_editor = null

func _create_ui():
	_edit_button = Button.new()
	_edit_button.pressed.connect(_on_edit_pressed)
	add_child(_edit_button)
	_update_button_text()

func _update_button_text():
	if not is_instance_valid(_target_object):
		return
	
	var current_array: PackedVector2Array = _target_object.get(_property_name)
	
	if current_array.size() < 3:
		var points_needed = 3 - current_array.size()
		if current_array.size() == 0:
			_edit_button.text = "Add 3 Default Points"
		else:
			_edit_button.text = "Add %d More Points" % points_needed
	elif _is_editing:
		_edit_button.text = "Stop Editing"
	else:
		_edit_button.text = "Edit in 2D View"

func _on_edit_pressed():
	if not is_instance_valid(_target_object):
		return
	
	var current_array: PackedVector2Array = _target_object.get(_property_name)
	
	if current_array.size() < 3:
		_add_needed_points()
	elif _is_editing:
		_stop_editing()
	else:
		_start_editing()

func _add_needed_points():
	if not is_instance_valid(_polygon_editor):
		return
	
	var current_array: PackedVector2Array = _target_object.get(_property_name)
	var points_needed = 3 - current_array.size()
	
	# Create new array with existing points plus needed points
	var new_points = PackedVector2Array(current_array)
	
	# Add points based on what we already have
	match current_array.size():
		0:
			# No existing points - add default triangle
			new_points.append(Vector2(32.0, 0.0))
			new_points.append(Vector2(-32.0, 32.0))
			new_points.append(Vector2(-32.0, -32.0))
		1:
			# One existing point - add two more to form triangle
			var existing_point = current_array[0]
			new_points.append(existing_point + Vector2(64.0, 0.0))
			new_points.append(existing_point + Vector2(0.0, 64.0))
		2:
			# Two existing points - add one more to complete triangle
			var p1 = current_array[0]
			var p2 = current_array[1]
			# Create third point to form a triangle (perpendicular to the line between p1 and p2)
			var midpoint = (p1 + p2) * 0.5
			var direction = (p2 - p1).normalized()
			var perpendicular = Vector2(-direction.y, direction.x) * 32.0
			new_points.append(midpoint + perpendicular)
	
	# Use undo/redo for the operation
	var undo = _polygon_editor._plugin.get_undo_redo()
	undo.create_action("Add needed polygon points")
	undo.add_do_method(self, "_do_set_points", new_points)
	undo.add_undo_method(self, "_do_set_points", current_array)
	undo.commit_action()
	
	# Start editing after adding points
	_start_editing()

func _do_set_points(points: PackedVector2Array):
	_target_object.set(_property_name, points)
	_update_button_text()

func _start_editing():
	if not is_instance_valid(_polygon_editor):
		return
	
	var current_array: PackedVector2Array = _target_object.get(_property_name)
	if current_array.size() < 3:
		return  # Can't edit with less than 3 points
	
	# Stop any other active editing first
	_polygon_editor.clear_current()
	
	_is_editing = true
	_polygon_editor.set_current(_target_object, _property_name)
	
	_edit_button.text = "Stop Editing"
	_edit_button.modulate = Color.GREEN
	
	print("Started editing ", _property_name, " on ", _target_object.name if _target_object.has_method("get_name") else str(_target_object))

func _stop_editing():
	if not is_instance_valid(_polygon_editor):
		_stop_editing_without_editor_call()
		return
	
	_polygon_editor.clear_current()
	_stop_editing_without_editor_call()

func _stop_editing_without_editor_call():
	_is_editing = false
	if is_instance_valid(_edit_button):
		_update_button_text()
		_edit_button.modulate = Color.WHITE

func _update_button_state():
	var should_enable = _target_object and _target_object is Node2D
	
	# Performance: Only update if state changed
	if _needs_button_update or should_enable != _last_button_state:
		_edit_button.disabled = not should_enable
		
		if not should_enable:
			_edit_button.tooltip_text = "This feature only works with Node2D objects"
		else:
			var current_array: PackedVector2Array = _target_object.get(_property_name)
			if current_array.size() < 3:
				var points_needed = 3 - current_array.size()
				if current_array.size() == 0:
					_edit_button.tooltip_text = "Click to add 3 default points and start editing"
				else:
					_edit_button.tooltip_text = "Click to add %d more points to complete polygon" % points_needed
			else:
				_edit_button.tooltip_text = "Click to edit this PackedVector2Array as a polygon in the 2D view"
		
		_last_button_state = should_enable
		_needs_button_update = false
