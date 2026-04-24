class_name NetworkDebugger
extends CanvasLayer
## Runtime debug overlay showing network metrics.
## Toggled with F12 by default.

var _label: Label
var _visible: bool = false
var _update_timer: float = 0.0
var _update_interval: float = 0.5  # seconds


func _ready() -> void:
	layer = 100
	_create_ui()
	visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		toggle()


func toggle() -> void:
	_visible = not _visible
	visible = _visible


func show_overlay() -> void:
	_visible = true
	visible = true


func hide_overlay() -> void:
	_visible = false
	visible = false


func _process(delta: float) -> void:
	if not _visible:
		return

	_update_timer += delta
	if _update_timer >= _update_interval:
		_update_timer = 0.0
		_refresh_display()


func _create_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-320, 10)
	panel.size = Vector2(310, 200)
	panel.custom_minimum_size = Vector2(310, 200)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.75)
	style.border_color = Color(0.3, 0.8, 0.3, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	_label = Label.new()
	_label.text = "LinkUx Debug"
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	panel.add_child(_label)

	add_child(panel)


func _refresh_display() -> void:
	var linkux: Node = get_tree().root.get_node_or_null("LinkUx")
	if linkux == null:
		_label.text = "LinkUx: Not found"
		return

	var text := "=== LinkUx Debug ===\n"

	if linkux.has_method("get_debug_metrics"):
		var metrics: Dictionary = linkux.get_debug_metrics()
		text += "State: %s\n" % metrics.get("state", "?")
		text += "Backend: %s\n" % metrics.get("backend", "?")
		text += "Tick: %d\n" % metrics.get("tick", 0)
		text += "Peers: %d\n" % metrics.get("peers", 0)

	if linkux.has_method("is_host"):
		text += "Role: %s\n" % ("Host" if linkux.is_host() else "Client")

	if linkux.has_method("get_local_peer_id"):
		text += "Local Peer ID: %d\n" % linkux.get_local_peer_id()

	if linkux.has_method("get_network_stats"):
		var stats: Dictionary = linkux.get_network_stats()
		for peer_id: int in stats:
			var peer_stats: Dictionary = stats[peer_id]
			text += "Peer %d RTT: %.1fms\n" % [peer_id, peer_stats.get("rtt_ms", -1)]

	_label.text = text
