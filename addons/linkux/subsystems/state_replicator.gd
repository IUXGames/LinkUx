class_name StateReplicator
extends Node
## Handles per-tick state replication of registered entities and global game state.
## Integrates with DeltaCompressor for bandwidth optimization.

var _transport: TransportLayer
var _events: NetworkEvents
var _logger: DebugLogger
var _config: NetworkConfig
var _debug_hooks: DebugHooks

## Entity registry: NodePath -> EntityEntry
var _registry: Dictionary = {}

## Path compression: NodePath -> int ID
var _path_to_id: Dictionary = {}
var _id_to_path: Dictionary = {}
var _next_path_id: int = 1

## Global state (host-authoritative)
var _global_state: Dictionary = {}

## Sequence counter
var _sequence: int = 0


class EntityEntry:
	var node: Node
	var properties: Array[String]
	var mode: int  # ReplicationMode
	var authority_peer: int = 1
	var last_snapshot: Dictionary = {}
	var path_id: int = 0


func setup(transport: TransportLayer, events: NetworkEvents, logger: DebugLogger, config: NetworkConfig, debug_hooks: DebugHooks) -> void:
	if _events:
		if _events.data_received.is_connected(_on_data_received):
			_events.data_received.disconnect(_on_data_received)
		if _events.authority_changed.is_connected(_on_authority_changed):
			_events.authority_changed.disconnect(_on_authority_changed)

	_transport = transport
	_events = events
	_logger = logger
	_config = config
	_debug_hooks = debug_hooks

	if _events:
		if not _events.data_received.is_connected(_on_data_received):
			_events.data_received.connect(_on_data_received)
		if not _events.authority_changed.is_connected(_on_authority_changed):
			_events.authority_changed.connect(_on_authority_changed)


## Reserva el siguiente id de entidad de red (solo debe usarlo el host al spawner antes del broadcast).
func allocate_entity_network_id() -> int:
	var id := _next_path_id
	_next_path_id += 1
	return id


func register_entity(entity: Node, properties: Array[String], mode: int, forced_net_id: int = -1) -> void:
	var path := entity.get_path()
	if _registry.has(path):
		_logger.debug("Entity already registered: %s" % str(path), "StateReplicator")
		return

	var entry := EntityEntry.new()
	entry.node = entity
	entry.properties = properties
	entry.mode = mode
	var chosen_id := forced_net_id
	if chosen_id >= 1 and _id_to_path.has(chosen_id):
		var existing_path: NodePath = _id_to_path[chosen_id]
		if existing_path != path:
			var ex_node: Node = entity.get_tree().root.get_node_or_null(existing_path)
			if ex_node != null:
				_logger.warn(
					"Replication id %d already mapped to %s; auto-assigning for %s" % [chosen_id, str(existing_path), str(path)],
					"StateReplicator",
				)
				chosen_id = -1
			else:
				## Stale map after despawn / reconnect with the same peer_id: reuse the network id.
				_id_to_path.erase(chosen_id)
				_path_to_id.erase(existing_path)
				if _registry.has(existing_path):
					_registry.erase(existing_path)
	if chosen_id >= 1:
		entry.path_id = chosen_id
	else:
		entry.path_id = _next_path_id
		_next_path_id += 1
	_next_path_id = maxi(_next_path_id, entry.path_id + 1)

	_path_to_id[path] = entry.path_id
	_id_to_path[entry.path_id] = path
	var linkux: Node = get_parent()
	## player_peer_id es la fuente de verdad en juegos tipo FPS; get_multiplayer_authority() en el
	## servidor puede seguir en 1 en puppets de clientes y romper _handle_full_state / relay.
	if "player_peer_id" in entity:
		entry.authority_peer = int(entity.get("player_peer_id"))
	elif linkux and linkux.has_method("get_entity_authority"):
		entry.authority_peer = linkux.get_entity_authority(entity)
	_registry[path] = entry

	_logger.debug("Entity registered: %s (id=%d, %d props)" % [str(path), entry.path_id, properties.size()], "StateReplicator")


func unregister_entity(entity: Node) -> void:
	var path := entity.get_path()
	if _registry.has(path):
		var entry: EntityEntry = _registry[path]
		_path_to_id.erase(path)
		_id_to_path.erase(entry.path_id)
		_registry.erase(path)
		_logger.debug("Entity unregistered: %s" % str(path), "StateReplicator")


func set_entity_authority(entity_path: NodePath, peer_id: int) -> void:
	if _registry.has(entity_path):
		_registry[entity_path].authority_peer = peer_id


func set_global_state(key: String, value: Variant) -> void:
	_global_state[key] = value

	# Broadcast to all peers
	_sequence = (_sequence + 1) % 256
	var tick := _get_current_tick()

	var payload := {"key": key, "value": value}
	var data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.GLOBAL_STATE_UPDATE, tick, _sequence, payload
	)
	_transport.broadcast(data, NetworkEnums.ChannelType.STATE, true)
	_events.global_state_changed.emit(key, value)


func get_global_state(key: String, default: Variant = null) -> Variant:
	return _global_state.get(key, default)


func get_full_snapshot() -> Dictionary:
	## Returns a complete snapshot of all entities + global state (for late joiners).
	var entities: Array[Dictionary] = []
	for path: NodePath in _registry:
		var entry: EntityEntry = _registry[path]
		if not is_instance_valid(entry.node):
			continue
		var snapshot := _capture_snapshot(entry)
		entities.append({
			"path": str(path),
			"path_id": entry.path_id,
			"properties": entry.properties,
			"mode": entry.mode,
			"authority": entry.authority_peer,
			"state": snapshot,
		})

	return {
		"entities": entities,
		"global_state": _global_state.duplicate(),
		"path_map": _path_to_id.duplicate(),
	}


func apply_full_snapshot(snapshot: Dictionary) -> void:
	## Applies a full world snapshot (for late joiners).
	var global: Dictionary = snapshot.get("global_state", {})
	for key: String in global:
		_global_state[key] = global[key]
		_events.global_state_changed.emit(key, global[key])

	var entities: Array = snapshot.get("entities", [])
	for entity_data: Dictionary in entities:
		var want_path_id: int = int(entity_data.get("path_id", 0))
		var want_auth: int = int(entity_data.get("authority", 0))
		var node: Node = null
		if want_path_id >= 1 and _id_to_path.has(want_path_id):
			node = get_node_or_null(_id_to_path[want_path_id])
		if (node == null or not is_instance_valid(node)) and want_auth >= 1:
			node = _find_node_with_player_peer_id(want_auth)
		if node == null or not is_instance_valid(node):
			var host_path := NodePath(entity_data.get("path", ""))
			node = get_node_or_null(host_path)
		if node == null or not is_instance_valid(node):
			_logger.warn("Late join: entity not found (path_id=%d authority=%d)" % [want_path_id, want_auth], "StateReplicator")
			continue

		var local_path := node.get_path()
		if _registry.has(local_path):
			var reg_entry: EntityEntry = _registry[local_path]
			reg_entry.authority_peer = int(entity_data.get("authority", reg_entry.authority_peer))

		var state: Dictionary = entity_data.get("state", {})
		var local_peer := _get_local_peer_id()
		if local_peer >= 1:
			var skip_own_pose := false
			if "player_peer_id" in node:
				skip_own_pose = int(node.get("player_peer_id")) == local_peer
			else:
				var tree := get_tree()
				if tree and tree.multiplayer and tree.multiplayer.has_multiplayer_peer():
					skip_own_pose = node.get_multiplayer_authority() == local_peer
				else:
					var lx: Node = get_parent()
					if lx and lx.has_method("is_entity_authority"):
						skip_own_pose = lx.is_entity_authority(node)
			if skip_own_pose:
				continue
		_apply_state_to_node(node, state)


func process_tick(tick: int, _delta: float) -> void:
	var entities_replicated := 0

	for path: NodePath in _registry:
		var entry: EntityEntry = _registry[path]
		if not is_instance_valid(entry.node):
			continue

		# Only authority peer sends state
		var local_peer := _get_local_peer_id()
		if entry.authority_peer != local_peer:
			continue

		var snapshot := _capture_snapshot(entry)

		match entry.mode:
			NetworkEnums.ReplicationMode.ALWAYS:
				_send_full_state(entry, snapshot, tick)
				entities_replicated += 1
			NetworkEnums.ReplicationMode.ON_CHANGE:
				var delta := DeltaCompressor.compute_delta(entry.last_snapshot, snapshot)
				if not delta.is_empty():
					_send_delta_state(entry, delta, tick)
					entities_replicated += 1
			NetworkEnums.ReplicationMode.MANUAL:
				pass

		entry.last_snapshot = snapshot

	if _debug_hooks and _debug_hooks.enabled:
		_debug_hooks.log_tick(tick, _delta, entities_replicated)


func clear_all() -> void:
	_registry.clear()
	_path_to_id.clear()
	_id_to_path.clear()
	_next_path_id = 1
	_global_state.clear()


# ── Internal ─────────────────────────────────────────────────────────────────

func _find_node_with_player_peer_id(want_peer_id: int) -> Node:
	return _find_node_with_player_peer_id_recursive(get_tree().root, want_peer_id)


func _find_node_with_player_peer_id_recursive(n: Node, want_peer_id: int) -> Node:
	if n != null and "player_peer_id" in n and int(n.get("player_peer_id")) == want_peer_id:
		return n
	if n == null:
		return null
	for c in n.get_children():
		var found := _find_node_with_player_peer_id_recursive(c, want_peer_id)
		if found != null:
			return found
	return null


func _on_authority_changed(entity: Node, new_authority: int) -> void:
	if entity == null or not is_instance_valid(entity) or not entity.is_inside_tree():
		return
	var path := entity.get_path()
	if _registry.has(path):
		_registry[path].authority_peer = new_authority


func _capture_snapshot(entry: EntityEntry) -> Dictionary:
	var snapshot: Dictionary = {}
	for prop: String in entry.properties:
		if ":" in prop:
			var colon := prop.find(":")
			var child := entry.node.get_node_or_null(prop.left(colon))
			if child != null:
				var prop_name := prop.right(prop.length() - colon - 1)
				snapshot[prop] = child.get(prop_name)
		elif entry.node.has_method("get") or prop in entry.node:
			snapshot[prop] = entry.node.get(prop)
	return snapshot


func _apply_state_to_node(node: Node, state: Dictionary) -> void:
	if state.is_empty():
		return
	## Let LinkUxSynchronizer smooth position/rotation between network ticks (~30 Hz).
	var sync_node := _find_primary_synchronizer(node)
	if sync_node and sync_node.has_method("apply_remote_state"):
		sync_node.apply_remote_state(state)
		return
	for prop: String in state:
		if prop in node:
			node.set(prop, state[prop])


func _find_primary_synchronizer(entity_root: Node) -> Node:
	if entity_root == null:
		return null
	var found: Array[Node] = []
	for child: Node in entity_root.get_children():
		if child != null and child.has_method("apply_remote_state") and child.has_method("_register"):
			found.append(child)
	if found.is_empty():
		return null
	if found.size() > 1:
		_logger.warn(
			"Multiple LinkUxSynchronizer-like nodes found under %s. Using '%s' and ignoring %d duplicate(s)." % [str(entity_root.get_path()), found[0].name, found.size() - 1],
			"StateReplicator"
		)
	return found[0]


func _send_full_state(entry: EntityEntry, snapshot: Dictionary, tick: int) -> void:
	_sequence = (_sequence + 1) % 256
	var payload := {
		"path_id": entry.path_id,
		"state": snapshot,
	}
	var data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.STATE_FULL, tick, _sequence, payload
	)
	_transport.broadcast(data, NetworkEnums.ChannelType.STATE, false)


func _send_delta_state(entry: EntityEntry, delta: Dictionary, tick: int) -> void:
	_sequence = (_sequence + 1) % 256
	var payload := {
		"path_id": entry.path_id,
		"delta": delta,
	}
	var data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.STATE_DELTA, tick, _sequence, payload
	)
	_transport.broadcast(data, NetworkEnums.ChannelType.STATE, false)


func _on_data_received(from_peer: int, _channel: int, data: PackedByteArray) -> void:
	if data.size() < MessageSerializer.HEADER_SIZE:
		return

	var header := MessageSerializer.deserialize_header(data)
	var msg_type: int = header.get("type", -1)

	match msg_type:
		NetworkEnums.MessageType.STATE_FULL:
			_handle_full_state(from_peer, data)
		NetworkEnums.MessageType.STATE_DELTA:
			_handle_delta_state(from_peer, data)
		NetworkEnums.MessageType.GLOBAL_STATE_UPDATE:
			_handle_global_state_update(from_peer, data)


func _handle_full_state(from_peer: int, data: PackedByteArray) -> void:
	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return

	var path_id: int = payload.get("path_id", 0)
	var state: Dictionary = payload.get("state", {})
	var path: NodePath = _id_to_path.get(path_id, NodePath())

	if path == NodePath() or not _registry.has(path):
		return

	var entry: EntityEntry = _registry[path]
	if not is_instance_valid(entry.node):
		return

	# Don't apply if we are the authority
	if entry.authority_peer == _get_local_peer_id():
		return

	_apply_state_to_node(entry.node, state)
	entry.last_snapshot = state

	# ENet server mode: each client is only connected to the host. A client's STATE_* packets
	# reach the host but not other clients; the host must relay them.
	_relay_state_packet_if_host(from_peer, entry, data)


func _handle_delta_state(from_peer: int, data: PackedByteArray) -> void:
	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return

	var path_id: int = payload.get("path_id", 0)
	var delta: Dictionary = payload.get("delta", {})
	var path: NodePath = _id_to_path.get(path_id, NodePath())

	if path == NodePath() or not _registry.has(path):
		return

	var entry: EntityEntry = _registry[path]
	if not is_instance_valid(entry.node):
		return

	if entry.authority_peer == _get_local_peer_id():
		return

	var new_state := DeltaCompressor.apply_delta(entry.last_snapshot, delta)
	_apply_state_to_node(entry.node, new_state)
	entry.last_snapshot = new_state

	_relay_state_packet_if_host(from_peer, entry, data)


func _handle_global_state_update(from_peer: int, data: PackedByteArray) -> void:
	if from_peer != 1:
		return
	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return

	var key: String = payload.get("key", "")
	var value: Variant = payload.get("value", null)

	if key != "":
		_global_state[key] = value
		_events.global_state_changed.emit(key, value)


func _get_current_tick() -> int:
	var tick_manager: Node = get_parent().get_node_or_null("TickManager")
	if tick_manager and tick_manager.has_method("get_current_tick"):
		return tick_manager.get_current_tick()
	return 0


func _get_local_peer_id() -> int:
	var linkux: Node = get_parent()
	if linkux and linkux.has_method("get_local_peer_id"):
		return linkux.get_local_peer_id()
	return -1


func _relay_state_packet_if_host(from_peer: int, entry: EntityEntry, data: PackedByteArray) -> void:
	if _get_local_peer_id() != 1:
		return
	if not _transport.has_method("host_should_relay_client_state") or not _transport.host_should_relay_client_state():
		return
	if from_peer != entry.authority_peer:
		return
	var linkux: Node = get_parent()
	if linkux == null or not linkux.has_method("get_connected_peers"):
		return
	for pid: int in linkux.get_connected_peers():
		if pid == from_peer:
			continue
		_transport.send(pid, data, NetworkEnums.ChannelType.STATE, false)
