@tool
class_name Vector2ArrayInspectorPlugin
extends EditorInspectorPlugin

var _polygon_editor: PolygonEditor
var _property_editors: Array[Vector2ArrayPropertyEditor] = []

func setup(polygon_editor: PolygonEditor):
	_polygon_editor = polygon_editor

func cleanup():
	print("inspector cleanup")
	for editor in _property_editors:
		if is_instance_valid(editor):
			editor.cleanup()
	_property_editors.clear()
	_polygon_editor = null

func _can_handle(object):
	return true

func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool):
	if type == TYPE_PACKED_VECTOR2_ARRAY:
		print("Found PackedVector2Array property: ", name)
		var property_editor = Vector2ArrayPropertyEditor.new()
		property_editor.setup(_polygon_editor, object, name)
		
		# Track the editor for cleanup
		_property_editors.append(property_editor)
		property_editor.tree_exiting.connect(_on_property_editor_removed.bind(property_editor))
		
		add_custom_control(property_editor)
		return false  # Don't replace the original property editor
	return false

func _on_property_editor_removed(editor: Vector2ArrayPropertyEditor):
	_property_editors.erase(editor)
