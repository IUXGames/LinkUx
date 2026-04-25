@tool
class_name LinkUxEditorStrings
extends RefCounted
## Static UI strings for LinkUx editor plugins (English only).


static func t(key: String) -> String:
	match key:
		"sync_header":
			return "Synchronized Properties"
		"add_sync_property":
			return "  Add Sync Property"
		"refresh_list":
			return "Refresh List"
		"refresh_tooltip":
			return "Force inspector rebuild and refresh the list"
		"no_props_yet":
			return "No properties synchronized yet."
		"remove_tooltip":
			return "Remove from synchronized properties"
		"node_not_found":
			return "Node not found: %s"
		"picker_title":
			return "Add Sync Property"
		"picker_hint":
			return "Select a node, then double-click a property — or select it and press Add Property."
		"scene_nodes":
			return "Scene Nodes"
		"properties":
			return "Properties"
		"search_placeholder":
			return "Search properties..."
		"col_property":
			return "Property"
		"col_type":
			return "Type"
		"add_property":
			return "Add Property"
		"undo_add":
			return "Add Sync Property"
		"undo_remove":
			return "Remove Sync Property"
		_:
			return key
