class_name AuthorityManager
extends Node
## Manages per-entity authority with validation, locks, and transfer protocol.

var _transport: TransportLayer
var _events: NetworkEvents
var _logger: DebugLogger
var _transfer_handler: AuthorityTransferHandler

## authority_map: NodePath -> {peer_id, mode, locked, version}
var _authority_map: Dictionary = {}

var _sequence: int = 0


func setup(transport: TransportLayer, events: NetworkEvents, logger: DebugLogger) -> void:
	if _events and _events.data_received.is_connected(_on_data_received):
		_events.data_received.disconnect(_on_data_received)
	if _transfer_handler:
		if _transfer_handler.transfer_completed.is_connected(_on_transfer_completed):
			_transfer_handler.transfer_completed.disconnect(_on_transfer_completed)
		if _transfer_handler.transfer_failed.is_connected(_on_transfer_failed):
			_transfer_handler.transfer_failed.disconnect(_on_transfer_failed)

	_transport = transport
	_events = events
	_logger = logger

	_transfer_handler = AuthorityTransferHandler.new()
	_transfer_handler.transfer_completed.connect(_on_transfer_completed)
	_transfer_handler.transfer_failed.connect(_on_transfer_failed)

	if _events and not _events.data_received.is_connected(_on_data_received):
		_events.data_received.connect(_on_data_received)


func set_authority(entity: Node, peer_id: int, mode: int = NetworkEnums.AuthorityMode.HOST) -> void:
	var path := entity.get_path()
	_authority_map[path] = {
		"peer_id": peer_id,
		"mode": mode,
		"locked": false,
		"version": _get_version(path) + 1,
	}

	# Sync with Godot's native system
	entity.set_multiplayer_authority(peer_id)

	# Only the host relays: on LAN (ENet server) clients only see the host; a broadcast from a
	# client does not reach everyone, and NodePaths are local to each machine.
	if _get_local_peer_id() == 1:
		_broadcast_authority_change(path, peer_id, mode)
	_events.authority_changed.emit(entity, peer_id)
	_logger.debug("Authority set: %s -> peer %d (mode=%d)" % [str(path), peer_id, mode], "AuthorityManager")


func get_authority(entity: Node) -> int:
	if entity == null or not is_instance_valid(entity):
		return 1
	var path := entity.get_path()
	if _authority_map.has(path):
		return int(_authority_map[path]["peer_id"])
	## No map entry: do not assume host. On the server (peer 1) that made `is_entity_authority`
	## true for client bodies, so the synchronizer dropped all remote state.
	var tree := get_tree()
	if tree and tree.multiplayer and tree.multiplayer.has_multiplayer_peer():
		return entity.get_multiplayer_authority()
	return 1


func get_authority_mode(entity: Node) -> int:
	var path := entity.get_path()
	if _authority_map.has(path):
		return _authority_map[path]["mode"]
	return NetworkEnums.AuthorityMode.HOST


func request_authority(entity: Node, requesting_peer: int) -> void:
	var path := entity.get_path()
	var current := get_authority(entity)
	var mode := get_authority_mode(entity)
	var locked := _transfer_handler.is_locked(path)

	if not AuthorityValidator.can_request_authority(path, requesting_peer, current, mode, locked):
		_logger.warn("Authority request denied for peer %d on %s" % [requesting_peer, str(path)], "AuthorityManager")
		return

	# Send request to host
	_sequence = (_sequence + 1) % 256
	var payload := {
		"path": str(path),
		"requesting_peer": requesting_peer,
	}
	var data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.AUTH_REQUEST, 0, _sequence, payload
	)
	_transport.send(1, data, NetworkEnums.ChannelType.CONTROL, true)
	_logger.debug("Authority requested: peer %d -> %s" % [requesting_peer, str(path)], "AuthorityManager")


func transfer_authority(entity: Node, to_peer: int) -> void:
	var path := entity.get_path()
	var current := get_authority(entity)
	var local_peer := _get_local_peer_id()

	if not AuthorityValidator.can_transfer_authority(path, local_peer, to_peer, current, _transfer_handler.is_locked(path)):
		_logger.warn("Authority transfer denied: %s -> peer %d" % [str(path), to_peer], "AuthorityManager")
		return

	if _transfer_handler.begin_transfer(path, current, to_peer):
		# Lock the entity
		if _authority_map.has(path):
			_authority_map[path]["locked"] = true

		# Send transfer begin to host
		_sequence = (_sequence + 1) % 256
		var payload := {
			"path": str(path),
			"from_peer": current,
			"to_peer": to_peer,
		}
		var data := MessageSerializer.serialize_message(
			NetworkEnums.MessageType.AUTH_TRANSFER_BEGIN, 0, _sequence, payload
		)
		_transport.send(1, data, NetworkEnums.ChannelType.CONTROL, true)


func validate_change(entity: Node, peer_id: int) -> bool:
	var path := entity.get_path()
	var entry: Dictionary = _authority_map.get(path, {})
	return entry.get("peer_id", 1) == peer_id


func on_peer_disconnected(peer_id: int) -> void:
	## Transfer all entities owned by disconnected peer to host.
	var paths_to_transfer: Array[NodePath] = []

	for path: NodePath in _authority_map:
		if _authority_map[path]["peer_id"] == peer_id:
			paths_to_transfer.append(path)

	for path: NodePath in paths_to_transfer:
		_authority_map[path]["peer_id"] = 1
		_authority_map[path]["locked"] = false

		var node := get_node_or_null(path)
		if node:
			node.set_multiplayer_authority(1)
			_events.authority_changed.emit(node, 1)

		_logger.info("Authority reverted to host for %s (peer %d disconnected)" % [str(path), peer_id], "AuthorityManager")


func get_authority_map_snapshot() -> Dictionary:
	## Por peer de red (no NodePath del host): en clientes el mismo path apunta a otro nodo.
	var by_peer: Dictionary = {}
	for map_key in _authority_map:
		var ent: Dictionary = _authority_map[map_key]
		var pid: int = int(ent.get("peer_id", 1))
		by_peer[str(pid)] = ent.duplicate(true)
	return {"by_network_peer": by_peer}


func apply_authority_map(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var by_peer: Dictionary = snapshot.get("by_network_peer", {}) as Dictionary
	if not by_peer.is_empty():
		for map_key in by_peer:
			var entry: Variant = by_peer[map_key]
			if not entry is Dictionary:
				continue
			var owning: int = int(entry.get("peer_id", 1))
			var node := _find_node_with_player_peer_id(owning)
			if node == null:
				continue
			var path := node.get_path()
			_authority_map[path] = entry
			node.set_multiplayer_authority(owning)
			_events.authority_changed.emit(node, owning)
		return
	## Formato antiguo: claves = NodePath del host (solo compatibilidad).
	for map_key in snapshot:
		if str(map_key) == "by_network_peer":
			continue
		var entry: Variant = snapshot[map_key]
		if not entry is Dictionary:
			continue
		var path := NodePath(str(map_key))
		_authority_map[path] = entry
		var peer_id: int = int(entry.get("peer_id", 1))
		var node := get_node_or_null(path)
		if node:
			node.set_multiplayer_authority(peer_id)


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


func unregister_entity_path(entity_path: NodePath) -> void:
	## Call when freeing the entity (same lifetime as StateReplicator.unregister_entity).
	if _authority_map.has(entity_path):
		_authority_map.erase(entity_path)


func clear_all() -> void:
	_authority_map.clear()


# ── Internal ─────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _transfer_handler:
		_transfer_handler.check_timeouts()


func _broadcast_authority_change(path: NodePath, peer_id: int, mode: int) -> void:
	_sequence = (_sequence + 1) % 256
	var payload := {
		"path": str(path),
		"peer_id": peer_id,
		"mode": mode,
		"version": _get_version(path),
	}
	var data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.AUTH_CHANGED, 0, _sequence, payload
	)
	_transport.broadcast(data, NetworkEnums.ChannelType.CONTROL, true)


func _on_data_received(from_peer: int, _channel: int, data: PackedByteArray) -> void:
	if data.size() < MessageSerializer.HEADER_SIZE:
		return

	var header := MessageSerializer.deserialize_header(data)
	var msg_type: int = header.get("type", -1)

	match msg_type:
		NetworkEnums.MessageType.AUTH_REQUEST:
			_handle_auth_request(from_peer, data)
		NetworkEnums.MessageType.AUTH_TRANSFER_BEGIN:
			_handle_transfer_begin(from_peer, data)
		NetworkEnums.MessageType.AUTH_TRANSFER_ACK:
			_handle_transfer_ack(from_peer, data)
		NetworkEnums.MessageType.AUTH_CHANGED:
			_handle_auth_changed(from_peer, data)


func _handle_auth_request(from_peer: int, data: PackedByteArray) -> void:
	# Only host processes requests
	if _get_local_peer_id() != 1:
		return

	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return

	var path := NodePath(payload.get("path", ""))
	var requesting_peer: int = payload.get("requesting_peer", from_peer)
	var current := _authority_map.get(path, {}).get("peer_id", 1) as int
	var mode := _authority_map.get(path, {}).get("mode", NetworkEnums.AuthorityMode.HOST) as int
	var locked := _transfer_handler.is_locked(path)

	if AuthorityValidator.can_request_authority(path, requesting_peer, current, mode, locked):
		var node := get_node_or_null(path)
		if node:
			set_authority(node, requesting_peer, mode)
	else:
		# Deny
		_sequence = (_sequence + 1) % 256
		var deny_payload := {"path": str(path), "peer_id": requesting_peer}
		var deny_data := MessageSerializer.serialize_message(
			NetworkEnums.MessageType.AUTH_DENIED, 0, _sequence, deny_payload
		)
		_transport.send(requesting_peer, deny_data, NetworkEnums.ChannelType.CONTROL, true)


func _handle_transfer_begin(from_peer: int, data: PackedByteArray) -> void:
	if _get_local_peer_id() != 1:
		return

	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return

	var path := NodePath(payload.get("path", ""))
	var to_peer: int = payload.get("to_peer", 0)

	if _transfer_handler.begin_transfer(path, from_peer, to_peer):
		if _authority_map.has(path):
			_authority_map[path]["locked"] = true
		# Confirm transfer
		_transfer_handler.confirm_transfer(path)


func _handle_transfer_ack(_from_peer: int, data: PackedByteArray) -> void:
	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return
	var path := NodePath(payload.get("path", ""))
	_transfer_handler.confirm_transfer(path)


func _handle_auth_changed(_from_peer: int, data: PackedByteArray) -> void:
	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return

	var path := NodePath(payload.get("path", ""))
	var peer_id: int = payload.get("peer_id", 1)
	var mode: int = payload.get("mode", NetworkEnums.AuthorityMode.HOST)
	var version: int = payload.get("version", 0)

	# Only apply if version is newer
	if version <= _get_version(path):
		return

	_authority_map[path] = {
		"peer_id": peer_id,
		"mode": mode,
		"locked": false,
		"version": version,
	}

	var node := get_node_or_null(path)
	if node:
		node.set_multiplayer_authority(peer_id)
		_events.authority_changed.emit(node, peer_id)


func _on_transfer_completed(entity_path: NodePath, new_authority: int) -> void:
	if _authority_map.has(entity_path):
		_authority_map[entity_path]["peer_id"] = new_authority
		_authority_map[entity_path]["locked"] = false
		_authority_map[entity_path]["version"] = _get_version(entity_path) + 1

	var node := get_node_or_null(entity_path)
	if node:
		node.set_multiplayer_authority(new_authority)
		_broadcast_authority_change(entity_path, new_authority, _authority_map.get(entity_path, {}).get("mode", 0))
		_events.authority_changed.emit(node, new_authority)

	_logger.info("Authority transfer completed: %s -> peer %d" % [str(entity_path), new_authority], "AuthorityManager")


func _on_transfer_failed(entity_path: NodePath, reason: String) -> void:
	if _authority_map.has(entity_path):
		_authority_map[entity_path]["locked"] = false
	_logger.warn("Authority transfer failed for %s: %s" % [str(entity_path), reason], "AuthorityManager")


func _get_version(path: NodePath) -> int:
	if _authority_map.has(path):
		return _authority_map[path].get("version", 0)
	return 0


func _get_local_peer_id() -> int:
	var linkux: Node = get_parent()
	if linkux and linkux.has_method("get_local_peer_id"):
		return linkux.get_local_peer_id()
	return -1
