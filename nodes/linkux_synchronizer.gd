@icon("res://addons/linkux/icons/Icon_LinkUxSynchronizer.svg")
class_name LinkUxSynchronizer
extends Node
## Per-node property synchronizer with optional interpolation.
## Integrates with StateReplicator: incoming state is applied via apply_remote_state().
##
## sync_properties format:
##   "property"            → property on the parent node (entity root)
##   "ChildNode:property"  → property on a child node (NodePath relative to parent)

@export var sync_properties: Array[String] = []
@export var replication_mode: NetworkEnums.ReplicationMode = NetworkEnums.ReplicationMode.ALWAYS
@export var interpolate: bool = true
## How fast to blend toward the latest network state (higher = less smooth lag).
@export_range(2.0, 45.0) var remote_smoothing_hz: float = 16.0

var position_snap_epsilon: float = 0.0002
var rotation_snap_epsilon: float = 0.0002
var _target: Node
var _registered: bool = false
var _pending_state: Dictionary = {}
var _is_primary_synchronizer: bool = true


func _ready() -> void:
	_target = get_parent()
	_validate_single_synchronizer_per_target()
	call_deferred("_register")


func _exit_tree() -> void:
	if _target and _registered:
		var linkux := _get_linkux()
		if linkux and linkux.has_method("unregister_entity"):
			linkux.unregister_entity(_target)


func _process(delta: float) -> void:
	if not _is_primary_synchronizer:
		return
	if _target == null:
		return
	if _local_peer_owns_replicated_entity():
		if not _pending_state.is_empty():
			_pending_state.clear()
		return
	if _pending_state.is_empty():
		return

	if not interpolate:
		_flush_pending_immediate()
		return

	var step := clampf(remote_smoothing_hz * delta, 0.0, 1.0)
	var done_keys: Array[String] = []

	for prop: String in _pending_state.keys():
		var node: Node = _target
		var prop_name: String = prop
		if ":" in prop:
			var colon := prop.find(":")
			node = _target.get_node_or_null(prop.left(colon))
			prop_name = prop.right(prop.length() - colon - 1)

		if node == null or not (prop_name in node):
			done_keys.append(prop)
			continue

		var cur: Variant = node.get(prop_name)
		var tgt: Variant = _pending_state[prop]

		if cur is Vector3 and tgt is Vector3:
			var eps := position_snap_epsilon if prop_name == "position" else rotation_snap_epsilon
			if prop_name == "rotation":
				## Euler + Vector3.lerp cruza el corte −π/π: el "camino corto" en espacio lineal es un giro de 360°.
				var ax := absf(angle_difference(cur.x, tgt.x))
				var ay := absf(angle_difference(cur.y, tgt.y))
				var az := absf(angle_difference(cur.z, tgt.z))
				if ax <= eps and ay <= eps and az <= eps:
					node.set(prop_name, tgt)
					done_keys.append(prop)
				else:
					node.set(prop_name, Vector3(
						lerp_angle(cur.x, tgt.x, step),
						lerp_angle(cur.y, tgt.y, step),
						lerp_angle(cur.z, tgt.z, step)
					))
			elif cur.distance_squared_to(tgt) <= eps * eps:
				node.set(prop_name, tgt)
				done_keys.append(prop)
			else:
				node.set(prop_name, cur.lerp(tgt, step))
		else:
			node.set(prop_name, tgt)
			done_keys.append(prop)

	for k: String in done_keys:
		_pending_state.erase(k)


func apply_remote_state(state: Dictionary) -> void:
	if not _is_primary_synchronizer:
		return
	if _local_peer_owns_replicated_entity():
		_pending_state.clear()
		return
	if interpolate:
		_pending_state = state.duplicate()
	else:
		_flush_state_to_target(state)


func _flush_pending_immediate() -> void:
	_flush_state_to_target(_pending_state)
	_pending_state.clear()


func _flush_state_to_target(state: Dictionary) -> void:
	if _target == null:
		return
	for prop: String in state:
		var node: Node = _target
		var prop_name: String = prop
		if ":" in prop:
			var colon := prop.find(":")
			node = _target.get_node_or_null(prop.left(colon))
			prop_name = prop.right(prop.length() - colon - 1)
		if node != null and prop_name in node:
			node.set(prop_name, state[prop])


func _register() -> void:
	if not _is_primary_synchronizer:
		return
	if _target == null:
		return

	var linkux := _get_linkux()
	if linkux == null or not linkux.has_method("is_in_session"):
		return

	if linkux.is_in_session():
		var props: Array[String] = []
		for p: String in sync_properties:
			props.append(p)
		var net_id: int = -1
		if _target.has_meta("_linkux_net_entity_id"):
			net_id = int(_target.get_meta("_linkux_net_entity_id", -1))
			_target.remove_meta("_linkux_net_entity_id")
		linkux.register_entity(_target, props, replication_mode, net_id)
		_registered = true


func _get_linkux() -> Node:
	return get_tree().root.get_node_or_null("LinkUx")


func _local_peer_owns_replicated_entity() -> bool:
	var linkux := _get_linkux()
	if linkux == null or not linkux.has_method("is_in_session") or not linkux.is_in_session():
		return false
	if not linkux.has_method("get_local_peer_id"):
		return false
	var local_id: int = linkux.get_local_peer_id()
	if local_id < 1:
		return false
	## Same logic as gameplay (`player_peer_id`): do not rely on `get_multiplayer_authority()` alone —
	## on ENet server, client bodies often still have engine authority 1.
	if "player_peer_id" in _target:
		return int(_target.get("player_peer_id")) == local_id
	if linkux.has_method("is_entity_authority"):
		return linkux.is_entity_authority(_target)
	return false


func _validate_single_synchronizer_per_target() -> void:
	if _target == null:
		return
	var sync_nodes: Array[Node] = []
	for child: Node in _target.get_children():
		if child != null and child.has_method("apply_remote_state"):
			sync_nodes.append(child)
	if sync_nodes.size() <= 1:
		return
	var primary := sync_nodes[0]
	for i in range(1, sync_nodes.size()):
		var duplicate := sync_nodes[i]
		if duplicate == self:
			_is_primary_synchronizer = false
			push_warning("[LinkUx] WARN [LinkUxSynchronizer]: Multiple synchronizers detected under '%s'. '%s' will be ignored; primary is '%s'." % [str(_target.get_path()), name, primary.name])
			break
