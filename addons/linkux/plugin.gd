@tool
extends EditorPlugin

const AUTOLOAD_NAME := "LinkUx"
const AUTOLOAD_PATH := "res://addons/linkux/linkux.tscn"

var _sync_inspector_plugin: EditorInspectorPlugin


func _enter_tree() -> void:
	# Inspector plugins must be registered every editor session via _enter_tree,
	# not _enable_plugin (which only fires on the manual toggle, not on project load).
	var InspectorPluginScript := preload("nodes/editor/linkux_sync_inspector_plugin.gd")
	_sync_inspector_plugin = InspectorPluginScript.new(self)
	add_inspector_plugin(_sync_inspector_plugin)


func _exit_tree() -> void:
	if _sync_inspector_plugin:
		remove_inspector_plugin(_sync_inspector_plugin)
		_sync_inspector_plugin = null


func _enable_plugin() -> void:
	# Called once when the user first enables the plugin — persists autoload in project.godot.
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
