@tool
class_name Vector2ArrayInspectorPlugin
extends EditorInspectorPlugin

var _polygon_editor: PolygonEditor
var _property_editors: Array[Vector2ArrayPropertyEditor] = []

func setup(polygon_editor: PolygonEditor) -> void:
	_polygon_editor = polygon_editor

func cleanup() -> void:
	# Clean up all property editors with proper signal disconnection
	for editor: Vector2ArrayPropertyEditor in _property_editors:
		if is_instance_valid(editor):
			# Disconnect our tracking signal first
			if editor.tree_exiting.is_connected(_on_property_editor_removed):
				editor.tree_exiting.disconnect(_on_property_editor_removed)
			# Call the editor's cleanup method
			editor.cleanup()
	
	_property_editors.clear()
	_polygon_editor = null

func _can_handle(object: Object) -> bool:
	return true

func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool) -> bool:
	if type == TYPE_PACKED_VECTOR2_ARRAY:
		var property_editor: Vector2ArrayPropertyEditor = Vector2ArrayPropertyEditor.new()
		property_editor.setup(_polygon_editor, object, name)
		
		# Track the editor for cleanup
		_property_editors.append(property_editor)
		property_editor.tree_exiting.connect(_on_property_editor_removed.bind(property_editor))
		
		add_custom_control(property_editor)
		return false  # Don't replace the original property editor
	return false

func _on_property_editor_removed(editor: Vector2ArrayPropertyEditor) -> void:
	_property_editors.erase(editor)

func _is_editing() -> bool:
	return _property_editors.any(func (property_editor: Vector2ArrayPropertyEditor) -> bool: return property_editor._is_editing)
