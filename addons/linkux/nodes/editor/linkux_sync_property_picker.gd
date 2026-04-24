## Property picker dialog for LinkUxSynchronizer.
## Mirrors the look and flow of Godot's AnimationPlayer property selector:
##  - Left panel : scene node tree
##  - Right panel: categorised, collapsible property list with search
##  - Bottom bar : description of the currently-selected property
@tool
extends AcceptDialog

signal property_selected(property_path: String)

var _parent_node: Node
var _scene_root: Node

var _node_tree: Tree
var _prop_tree: Tree
var _search_bar: LineEdit
var _hint_label: Label
var _left_heading: Label
var _right_heading: Label


func _init() -> void:
	min_size = Vector2i(780, 500)
	_build_ui()
	apply_locale()
	confirmed.connect(_on_confirmed)


func apply_locale() -> void:
	title = LinkUxEditorStrings.t("picker_title")
	if _hint_label:
		_hint_label.text = LinkUxEditorStrings.t("picker_hint")
	if _left_heading:
		_left_heading.text = LinkUxEditorStrings.t("scene_nodes")
	if _right_heading:
		_right_heading.text = LinkUxEditorStrings.t("properties")
	if _search_bar:
		_search_bar.placeholder_text = LinkUxEditorStrings.t("search_placeholder")
	if _prop_tree:
		_prop_tree.set_column_title(0, LinkUxEditorStrings.t("col_property"))
		_prop_tree.set_column_title(1, LinkUxEditorStrings.t("col_type"))
	var ok := get_ok_button()
	if ok:
		ok.text = LinkUxEditorStrings.t("add_property")


func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 4)
	add_child(root_vbox)

	# Hint bar
	var hint := Label.new()
	_hint_label = hint
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	root_vbox.add_child(hint)

	root_vbox.add_child(_make_sep())

	# ── Main split ────────────────────────────────────────────────────────────
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.split_offset = 220
	root_vbox.add_child(split)

	# Left — node tree
	var left_box := VBoxContainer.new()
	left_box.custom_minimum_size = Vector2i(180, 0)
	left_box.add_theme_constant_override("separation", 4)
	split.add_child(left_box)

	var left_lbl := _make_panel_label("")
	_left_heading = left_lbl
	left_box.add_child(left_lbl)

	_node_tree = Tree.new()
	_node_tree.columns = 1
	_node_tree.hide_root = false
	_node_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_node_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_node_tree.item_selected.connect(_on_node_selected)
	left_box.add_child(_node_tree)

	# Right — property list
	var right_box := VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.add_theme_constant_override("separation", 4)
	split.add_child(right_box)

	var right_lbl := _make_panel_label("")
	_right_heading = right_lbl
	right_box.add_child(right_lbl)

	_search_bar = LineEdit.new()
	_search_bar.placeholder_text = LinkUxEditorStrings.t("search_placeholder")
	_search_bar.clear_button_enabled = true
	_search_bar.text_changed.connect(_on_search_changed)
	right_box.add_child(_search_bar)

	_prop_tree = Tree.new()
	_prop_tree.columns = 2
	_prop_tree.column_titles_visible = true
	_prop_tree.set_column_title(0, LinkUxEditorStrings.t("col_property"))
	_prop_tree.set_column_title(1, LinkUxEditorStrings.t("col_type"))
	_prop_tree.set_column_expand(0, true)
	_prop_tree.set_column_expand(1, false)
	_prop_tree.set_column_custom_minimum_width(1, 90)
	_prop_tree.hide_root = true
	_prop_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prop_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prop_tree.item_selected.connect(_on_prop_item_selected)
	_prop_tree.item_activated.connect(_on_prop_activated)
	right_box.add_child(_prop_tree)

	get_ok_button().text = LinkUxEditorStrings.t("add_property")
	get_ok_button().disabled = true


# ── Public ────────────────────────────────────────────────────────────────────

func open_for_node(parent_node: Node, scene_root: Node) -> void:
	_parent_node = parent_node
	_scene_root = scene_root if scene_root != null else parent_node
	_search_bar.text = ""
	get_ok_button().disabled = true
	_populate_node_tree()
	popup_centered()


# ── Node tree ─────────────────────────────────────────────────────────────────

func _populate_node_tree() -> void:
	_node_tree.clear()
	_prop_tree.clear()
	if _parent_node == null:
		return
	_add_node_item(_scene_root, null)
	var root_item := _node_tree.get_root()
	if root_item:
		var target := _find_tree_item(root_item, _parent_node)
		if target:
			target.select(0)
			_node_tree.scroll_to_item(target)
			_on_node_selected()


func _add_node_item(node: Node, parent_item: TreeItem) -> void:
	var item: TreeItem = (
		_node_tree.create_item(parent_item) if parent_item
		else _node_tree.create_item()
	)
	item.set_text(0, node.name)
	item.set_icon(0, _node_icon(node))
	item.set_metadata(0, node)
	for child in node.get_children():
		_add_node_item(child, item)


func _find_tree_item(item: TreeItem, target: Node) -> TreeItem:
	if item.get_metadata(0) == target:
		return item
	var child := item.get_first_child()
	while child:
		var found := _find_tree_item(child, target)
		if found:
			return found
		child = child.get_next()
	return null


func _on_node_selected() -> void:
	var item := _node_tree.get_selected()
	if item == null:
		return
	_populate_prop_tree(item.get_metadata(0) as Node, _search_bar.text)
	get_ok_button().disabled = true


# ── Property tree ─────────────────────────────────────────────────────────────

func _populate_prop_tree(node: Node, filter: String) -> void:
	_prop_tree.clear()
	if node == null:
		return

	var filter_lower := filter.to_lower()

	# Collect categories with their props first, then reverse before building.
	var categories: Array = []  # Array of {name: String, props: Array}
	var pending_cat := ""
	var pending_props: Array = []

	for prop in node.get_property_list():
		var name_str: String = prop["name"]
		var usage: int = prop["usage"]
		var type: int = prop["type"]

		if usage & PROPERTY_USAGE_CATEGORY:
			if pending_props.size() > 0:
				categories.append({"name": pending_cat, "props": pending_props})
			pending_cat = name_str
			pending_props = []
			continue

		if (usage & PROPERTY_USAGE_GROUP) or (usage & PROPERTY_USAGE_SUBGROUP):
			continue
		if not ((usage & PROPERTY_USAGE_EDITOR) or (usage & PROPERTY_USAGE_STORAGE)):
			continue
		if usage & PROPERTY_USAGE_INTERNAL:
			continue
		if type == TYPE_NIL:
			continue
		if name_str.begins_with("_"):
			continue
		if name_str == "script":
			continue
		if filter_lower != "" and not name_str.to_lower().contains(filter_lower):
			continue

		pending_props.append(prop)

	if pending_props.size() > 0:
		categories.append({"name": pending_cat, "props": pending_props})

	categories.reverse()

	var root := _prop_tree.create_item()
	for cat in categories:
		var cat_item := _prop_tree.create_item(root)
		_style_category(cat_item, cat["name"])
		for prop in cat["props"]:
			var type: int = prop["type"]
			var name_str: String = prop["name"]
			var item := _prop_tree.create_item(cat_item)
			item.set_icon(0, _type_icon(type as Variant.Type))
			item.set_text(0, name_str)
			item.set_text(1, _type_name(type as Variant.Type))
			item.set_metadata(0, name_str)
			item.set_metadata(1, prop)


func _style_category(item: TreeItem, cat_name: String) -> void:
	item.set_text(0, cat_name)
	item.set_selectable(0, false)
	item.set_selectable(1, false)
	item.collapsed = false
	item.set_custom_color(0, Color(0.7, 0.7, 0.7))
	if is_inside_tree() and has_theme_font("bold", "EditorFonts"):
		item.set_custom_font(0, get_theme_font("bold", "EditorFonts"))


func _on_search_changed(text: String) -> void:
	var sel := _node_tree.get_selected()
	if sel == null:
		return
	_populate_prop_tree(sel.get_metadata(0) as Node, text)
	get_ok_button().disabled = true


func _on_prop_item_selected() -> void:
	var sel := _prop_tree.get_selected()
	get_ok_button().disabled = (sel == null)


func _on_prop_activated() -> void:
	if _prop_tree.get_selected() != null and _node_tree.get_selected() != null:
		_on_confirmed()


# ── Confirm ───────────────────────────────────────────────────────────────────

func _on_confirmed() -> void:
	var node_item := _node_tree.get_selected()
	var prop_item := _prop_tree.get_selected()
	if node_item == null or prop_item == null:
		return
	if not (prop_item.get_metadata(0) is String):
		return

	var selected_node := node_item.get_metadata(0) as Node
	var prop_name: String = prop_item.get_metadata(0)

	var property_path: String
	if selected_node == _parent_node:
		property_path = prop_name
	else:
		property_path = "%s:%s" % [str(_parent_node.get_path_to(selected_node)), prop_name]

	property_selected.emit(property_path)
	hide()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_sep() -> HSeparator:
	return HSeparator.new()


func _make_panel_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	if is_inside_tree() and has_theme_font("bold", "EditorFonts"):
		lbl.add_theme_font_override("font", get_theme_font("bold", "EditorFonts"))
	return lbl


func _node_icon(node: Node) -> Texture2D:
	if not is_inside_tree():
		return null
	var cls := node.get_class()
	while cls != "":
		if has_theme_icon(cls, "EditorIcons"):
			return get_theme_icon(cls, "EditorIcons")
		cls = ClassDB.get_parent_class(cls)
	return null


func _type_icon(type: Variant.Type) -> Texture2D:
	if not is_inside_tree():
		return null
	var name := _type_icon_name(type)
	if has_theme_icon(name, "EditorIcons"):
		return get_theme_icon(name, "EditorIcons")
	if has_theme_icon("Variant", "EditorIcons"):
		return get_theme_icon("Variant", "EditorIcons")
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


func _type_name(type: Variant.Type) -> String:
	match type:
		TYPE_NIL: return "null"
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
		TYPE_CALLABLE: return "Callable"
		TYPE_SIGNAL: return "Signal"
		TYPE_DICTIONARY: return "Dictionary"
		TYPE_ARRAY: return "Array"
		_: return "Variant"
