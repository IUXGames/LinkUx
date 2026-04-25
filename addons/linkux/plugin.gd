@tool
extends EditorPlugin

const AUTOLOAD_NAME := "LinkUx"
const AUTOLOAD_PATH := "res://addons/linkux/linkux.tscn"
var link_github: String = "[url=https://github.com/IUXGames/LinkUx]Official GitHub Repository[/url]"
var link_website: String = "[url=https://iuxgames.github.io/LinkUx_WebSite/]Official Documentation WebSite[/url]"

var _sync_inspector_plugin: EditorInspectorPlugin
var LinkUxAutoload = preload("res://addons/linkux/linkux.gd")


func _enter_tree() -> void:
	var InspectorPluginScript := preload("nodes/editor/linkux_sync_inspector_plugin.gd")
	_sync_inspector_plugin = InspectorPluginScript.new(self)
	add_inspector_plugin(_sync_inspector_plugin)
	print_rich("LinkUx v%s | %s | %s" % [LinkUxAutoload.get_version(), link_github, link_website])


func _exit_tree() -> void:
	if _sync_inspector_plugin:
		remove_inspector_plugin(_sync_inspector_plugin)
		_sync_inspector_plugin = null


func _enable_plugin() -> void:
	# Called once when the user first enables the plugin — persists autoload in project.godot.
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	print("LinkUx plugin enabled")


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
	print("LinkUx plugin disabled")
