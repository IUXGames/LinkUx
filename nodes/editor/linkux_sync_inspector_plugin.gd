@tool
extends EditorInspectorPlugin

var _editor_plugin: EditorPlugin


func _init(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func _can_handle(object: Object) -> bool:
	return "sync_properties" in object and object.has_method("apply_remote_state")


func _parse_begin(object: Object) -> void:
	var PropEditorScript := preload("linkux_sync_prop_editor.gd")
	var editor := PropEditorScript.new()
	editor.setup(object, _editor_plugin)
	add_custom_control(editor)


func _parse_property(object: Object, type: Variant.Type, name: String,
		hint_type: PropertyHint, hint_string: String,
		usage_flags: int, wide: bool) -> bool:
	return name == "sync_properties"
