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

# Two-way sync: Track last known array state
var _last_known_array: PackedVector2Array = PackedVector2Array()
var _sync_timer: Timer

func _ready():
	# Force an update when the property editor is ready
	call_deferred("_force_sync_check")

func _force_sync_check():
	if is_instance_valid(_target_object):
		var current_array: PackedVector2Array = _target_object.get(_property_name)
		if not _arrays_equal(current_array, _last_known_array):
			_handle_external_array_change(current_array)

# Override update_property to catch when Godot updates the property
func update_property():
	super.update_property()  # Call parent implementation
	call_deferred("_force_sync_check")
	if _is_editing:
		_stop_editing()
	if _sync_timer:
		_sync_timer.queue_free()

func setup(polygon_editor: PolygonEditor, object: Object, prop_name: String):
	_polygon_editor = polygon_editor
	_target_object = object
	_property_name = prop_name
	
	_create_ui()
	_setup_sync_monitoring()
	_setup_property_notifications()
	_update_button_state()

func _setup_property_notifications():
	# Try to connect to the target object's property change signals if available
	if is_instance_valid(_target_object):
		# Many Node types emit changed signal when properties are modified
		if _target_object.has_signal("changed"):
			if not _target_object.changed.is_connected(_on_target_property_changed):
				_target_object.changed.connect(_on_target_property_changed)
		# Some objects have property_list_changed
		elif _target_object.has_signal("property_list_changed"):
			if not _target_object.property_list_changed.is_connected(_on_target_property_changed):
				_target_object.property_list_changed.connect(_on_target_property_changed)

func cleanup():
	if _is_editing:
		_stop_editing_without_editor_call()
	if _sync_timer:
		_sync_timer.queue_free()
		_sync_timer = null
	
	# Disconnect signals
	if is_instance_valid(_target_object):
		if _target_object.has_signal("changed") and _target_object.changed.is_connected(_on_target_property_changed):
			_target_object.changed.disconnect(_on_target_property_changed)
		elif _target_object.has_signal("property_list_changed") and _target_object.property_list_changed.is_connected(_on_target_property_changed):
			_target_object.property_list_changed.disconnect(_on_target_property_changed)
	
	_polygon_editor = null

func _create_ui():
	_edit_button = Button.new()
	_edit_button.pressed.connect(_on_edit_pressed)
	add_child(_edit_button)
	_update_button_text()

func _setup_sync_monitoring():
	# Create a timer to periodically check for external changes
	_sync_timer = Timer.new()
	_sync_timer.wait_time = 0.2  # Check 5 times per second (less frequent when not editing)
	_sync_timer.autostart = true  # Always start monitoring
	_sync_timer.timeout.connect(_check_for_external_changes)
	add_child(_sync_timer)
	
	# Initialize last known state
	if is_instance_valid(_target_object):
		_last_known_array = _target_object.get(_property_name).duplicate()

func _check_for_external_changes():
	if not is_instance_valid(_target_object):
		return
	
	# Check if we think we're editing but the polygon editor is not editing us
	if _is_editing and is_instance_valid(_polygon_editor):
		if _polygon_editor._current_property_editor != self:
			print("Detected that another editor took over - stopping editing")
			notify_stop_editing()
			return
	
	var current_array: PackedVector2Array = _target_object.get(_property_name)
	
	# Check if array has changed externally (not by our editor)
	if not _arrays_equal(current_array, _last_known_array):
		print("External change detected - old size: ", _last_known_array.size(), ", new size: ", current_array.size())
		_handle_external_array_change(current_array)

func _arrays_equal(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	
	return true

func _handle_external_array_change(new_array: PackedVector2Array):
	_last_known_array = new_array.duplicate()
	
	# ALWAYS update button text when array changes
	call_deferred("_update_button_text")
	
	# If we're currently editing, handle the change
	if _is_editing:
		if new_array.size() < 3:
			# Array has been reduced below minimum - stop editing
			print("Array reduced below 3 points - stopping editing")
			_stop_editing()
		else:
			# Array still valid - sync with polygon editor
			if is_instance_valid(_polygon_editor):
				_polygon_editor._polygon_data.vertices = new_array.duplicate()
				_polygon_editor._request_overlay_update()

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
	
	print("Button text updated to: ", _edit_button.text, " (array size: ", current_array.size(), ", is_editing: ", _is_editing, ")")

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
	
	# Start editing after adding points (this will properly handle multiple editors)
	call_deferred("_start_editing")

func _do_set_points(points: PackedVector2Array):
	_target_object.set(_property_name, points)
	_last_known_array = points.duplicate()  # Update our tracking
	# FORCE button text update immediately
	call_deferred("_update_button_text")

func _start_editing():
	if not is_instance_valid(_polygon_editor):
		return
	
	var current_array: PackedVector2Array = _target_object.get(_property_name)
	if current_array.size() < 3:
		return  # Can't edit with less than 3 points
	
	# Pass ourselves to the polygon editor so it can manage multiple editors
	_is_editing = true
	_polygon_editor.set_current(_target_object, _property_name, self)
	
	# Increase monitoring frequency while editing
	if _sync_timer:
		_sync_timer.wait_time = 0.05  # Check 20 times per second when editing
	
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
	
	# Reduce monitoring frequency when not editing
	if _sync_timer:
		_sync_timer.wait_time = 0.2  # Back to slower polling
	
	if is_instance_valid(_edit_button):
		_edit_button.modulate = Color.WHITE
		# FORCE button text update when stopping editing
		call_deferred("_update_button_text")

# Public method that can be called by PolygonEditor to notify this editor to stop
func notify_stop_editing():
	print("Property editor for ", _property_name, " notified to stop editing")
	_stop_editing_without_editor_call()

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

# Connect to property change notifications if available
func _on_target_property_changed():
	if is_instance_valid(_target_object):
		var current_array: PackedVector2Array = _target_object.get(_property_name)
		if not _arrays_equal(current_array, _last_known_array):
			_handle_external_array_change(current_array)

# PUBLIC METHOD: Called by PolygonEditor when vertices change
func refresh_button_text():
	call_deferred("_update_button_text")
