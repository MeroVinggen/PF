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
	_edit_button.text = "Edit in 2D View"
	_edit_button.pressed.connect(_on_edit_pressed)
	add_child(_edit_button)

func _on_edit_pressed():
	if _is_editing:
		_stop_editing()
	else:
		_start_editing()

func _start_editing():
	if not is_instance_valid(_polygon_editor):
		return
	
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
		_edit_button.text = "Edit in 2D View"
		_edit_button.modulate = Color.WHITE

func _update_button_state():
	var should_enable = _target_object and _target_object is Node2D
	
	# Performance: Only update if state changed
	if _needs_button_update or should_enable != _last_button_state:
		_edit_button.disabled = not should_enable
		_edit_button.tooltip_text = "Click to edit this PackedVector2Array as a polygon in the 2D view" if should_enable else "This feature only works with Node2D objects"
		_last_button_state = should_enable
		_needs_button_update = false
