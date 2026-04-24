@tool
extends VBoxContainer

var _object: Object
var _editor_plugin: EditorPlugin
var _undo_redo: EditorUndoRedoManager
var _rows_box: VBoxContainer
var _add_btn: Button
var _refresh_btn: Button
var _picker: AcceptDialog


func setup(object: Object, plugin: EditorPlugin) -> void:
	_object = object
	_editor_plugin = plugin
	_undo_redo = _editor_plugin.get_undo_redo()
	_build_ui()
	if _object.has_signal("property_list_changed"):
		_object.property_list_changed.connect(_refresh)
	if _undo_redo != null and _undo_redo.has_signal("version_changed"):
		if not _undo_redo.version_changed.is_connected(_on_undo_redo_version_changed):
			_undo_redo.version_changed.connect(_on_undo_redo_version_changed)


func _exit_tree() -> void:
	if _object != null and is_instance_valid(_object):
		if _object.has_signal("property_list_changed"):
			if _object.property_list_changed.is_connected(_refresh):
				_object.property_list_changed.disconnect(_refresh)
	if _undo_redo != null and _undo_redo.has_signal("version_changed"):
		if _undo_redo.version_changed.is_connected(_on_undo_redo_version_changed):
			_undo_redo.version_changed.disconnect(_on_undo_redo_version_changed)


# ── Build ─────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	# Header label — matches Godot's inspector section style
	var header := Label.new()
	header.text = LinkUxEditorStrings.t("sync_header")
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	add_child(header)

	# Dark rounded panel for the property rows
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.85)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 2)
	panel.add_child(_rows_box)

	# Action buttons
	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 4)
	add_child(actions)

	_add_btn = Button.new()
	_add_btn.text = LinkUxEditorStrings.t("add_sync_property")
	_add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_add_btn.pressed.connect(_on_add_pressed)
	actions.add_child(_add_btn)

	_refresh_btn = Button.new()
	_refresh_btn.text = LinkUxEditorStrings.t("refresh_list")
	_refresh_btn.tooltip_text = LinkUxEditorStrings.t("refresh_tooltip")
	_refresh_btn.pressed.connect(_on_refresh_pressed)
	actions.add_child(_refresh_btn)

	var PickerScript := preload("linkux_sync_property_picker.gd")
	_picker = PickerScript.new()
	_picker.property_selected.connect(_on_property_selected)
	add_child(_picker)


func _ready() -> void:
	if has_theme_icon("Add", "EditorIcons"):
		_add_btn.icon = get_theme_icon("Add", "EditorIcons")
	if has_theme_icon("Reload", "EditorIcons"):
		_refresh_btn.icon = get_theme_icon("Reload", "EditorIcons")
	_refresh()


# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if not is_instance_valid(_rows_box) or not is_inside_tree():
		return

	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()

	if not is_instance_valid(_object):
		return

	var props := _as_string_array(_object.get("sync_properties"))
	var parent: Node = (_object as Node).get_parent() if _object is Node else null

	if props.is_empty():
		var empty := Label.new()
		empty.text = LinkUxEditorStrings.t("no_props_yet")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_rows_box.add_child(empty)
		return

	for i in props.size():
		_rows_box.add_child(_build_row(props[i], i, parent))


func _build_row(prop_str: String, index: int, parent: Node) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)

	var resolved: Node = parent
	var prop_name := prop_str
	var node_path := ""
	if ":" in prop_str:
		var colon := prop_str.find(":")
		node_path = prop_str.left(colon)
		prop_name = prop_str.right(prop_str.length() - colon - 1)
		if parent:
			resolved = parent.get_node_or_null(node_path)

	var node_ok := resolved != null

	# Node-type icon
	var node_tex := _icon_rect()
	if node_ok:
		node_tex.texture = _node_icon(resolved)
	row.add_child(node_tex)

	# Property-type icon
	var type_tex := _icon_rect()
	if node_ok:
		type_tex.texture = _prop_type_icon(resolved, prop_name)
	row.add_child(type_tex)

	# Label
	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	if node_path != "":
		lbl.text = "%s  ›  %s" % [node_path, prop_name]
		lbl.add_theme_color_override("font_color",
			Color(1.0, 0.45, 0.3) if not node_ok else Color(0.78, 0.78, 0.78))
		if not node_ok:
			lbl.tooltip_text = LinkUxEditorStrings.t("node_not_found") % node_path
	else:
		lbl.text = prop_name
	row.add_child(lbl)

	# Remove button
	var del := Button.new()
	del.flat = true
	del.tooltip_text = LinkUxEditorStrings.t("remove_tooltip")
	if has_theme_icon("Remove", "EditorIcons"):
		del.icon = get_theme_icon("Remove", "EditorIcons")
	del.pressed.connect(_on_remove.bind(index))
	row.add_child(del)

	return row


func _icon_rect() -> TextureRect:
	var r := TextureRect.new()
	r.custom_minimum_size = Vector2i(16, 16)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	return r


# ── Callbacks ─────────────────────────────────────────────────────────────────

func _on_add_pressed() -> void:
	if not is_instance_valid(_object) or not _object is Node:
		return
	var parent: Node = (_object as Node).get_parent()
	if parent == null:
		return
	_picker.open_for_node(parent, get_tree().get_edited_scene_root())


func _on_refresh_pressed() -> void:
	call_deferred("_refresh")


func _on_remove(index: int) -> void:
	if not is_instance_valid(_object):
		return
	var old := _as_string_array(_object.get("sync_properties"))
	var work: Array[String] = []
	for p in old:
		work.append(p)
	if index >= 0 and index < work.size():
		work.remove_at(index)
	var nw := _copy_strings(work)
	_commit(nw, old, LinkUxEditorStrings.t("undo_remove"))


func _on_property_selected(path: String) -> void:
	if not is_instance_valid(_object):
		return
	var old := _as_string_array(_object.get("sync_properties"))
	if path in old:
		return
	var work: Array[String] = []
	for p in old:
		work.append(p)
	work.append(path)
	var nw := _copy_strings(work)
	_commit(nw, old, LinkUxEditorStrings.t("undo_add"))


func _commit(new_props: Array[String], old_props: Array[String], action: String) -> void:
	# Apply immediately so UI reflects the new value even if UndoRedo is delayed.
	_set_sync_properties(new_props)

	var ur: EditorUndoRedoManager = _editor_plugin.get_undo_redo()
	ur.create_action(action)
	ur.add_do_method(_object, "set", "sync_properties", _copy_strings(new_props))
	ur.add_undo_method(_object, "set", "sync_properties", _copy_strings(old_props))
	if _object != null and _object.has_method("notify_property_list_changed"):
		ur.add_do_method(_object, "notify_property_list_changed")
		ur.add_undo_method(_object, "notify_property_list_changed")
	ur.commit_action()


func _on_undo_redo_version_changed() -> void:
	call_deferred("_refresh")


func _force_inspector_refresh() -> void:
	if _editor_plugin == null or not is_instance_valid(_object):
		return
	var editor := _editor_plugin.get_editor_interface()
	if editor == null:
		return
	# Re-inspect current object so custom controls are rebuilt with latest values.
	editor.inspect_object(_object, "", true)


func _set_sync_properties(props: Array[String]) -> void:
	if not is_instance_valid(_object):
		return
	_object.set("sync_properties", _copy_strings(props))
	if _object.has_method("notify_property_list_changed"):
		_object.notify_property_list_changed()
	call_deferred("_force_inspector_refresh")
	call_deferred("_refresh")


func _as_string_array(value: Variant) -> Array[String]:
	if value is PackedStringArray:
		var from_packed: Array[String] = []
		for item in value:
			from_packed.append(str(item))
		return from_packed
	if value is Array:
		return _copy_strings(value)
	return []


func _copy_strings(values: Array) -> Array[String]:
	var copied: Array[String] = []
	for value in values:
		copied.append(str(value))
	return copied


# ── Icon helpers ──────────────────────────────────────────────────────────────

func _node_icon(node: Node) -> Texture2D:
	var cls := node.get_class()
	while cls != "":
		if has_theme_icon(cls, "EditorIcons"):
			return get_theme_icon(cls, "EditorIcons")
		cls = ClassDB.get_parent_class(cls)
	return null


func _prop_type_icon(node: Node, prop_name: String) -> Texture2D:
	for p in node.get_property_list():
		if p["name"] == prop_name:
			var n := _type_icon_name(p["type"] as Variant.Type)
			if has_theme_icon(n, "EditorIcons"):
				return get_theme_icon(n, "EditorIcons")
	return null


func _type_icon_name(type: Variant.Type) -> String:
	match type:
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR2I: return "Vector2i"
		TYPE_RECT2: return "Rect2"
		TYPE_RECT2I: return "Rect2i"
		TYPE_VECTOR3: return "Vector3"
		TYPE_VECTOR3I: return "Vector3i"
		TYPE_TRANSFORM2D: return "Transform2D"
		TYPE_VECTOR4: return "Vector4"
		TYPE_VECTOR4I: return "Vector4i"
		TYPE_PLANE: return "Plane"
		TYPE_QUATERNION: return "Quaternion"
		TYPE_AABB: return "AABB"
		TYPE_BASIS: return "Basis"
		TYPE_TRANSFORM3D: return "Transform3D"
		TYPE_COLOR: return "Color"
		TYPE_NODE_PATH: return "NodePath"
		TYPE_RID: return "RID"
		TYPE_OBJECT: return "Object"
		TYPE_DICTIONARY: return "Dictionary"
		TYPE_ARRAY: return "Array"
		_: return "Variant"
