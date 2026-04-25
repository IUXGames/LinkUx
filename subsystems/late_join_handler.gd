class_name LateJoinHandler
extends Node
## Handles sending a complete WorldSnapshot to peers that join mid-game.

var _transport: TransportLayer
var _events: NetworkEvents
var _logger: DebugLogger
var _state_replicator: Node  # StateReplicator
var _authority_manager: Node  # AuthorityManager

var _sequence: int = 0


func setup(transport: TransportLayer, events: NetworkEvents, logger: DebugLogger, state_replicator: Node, authority_manager: Node) -> void:
	if _events and _events.data_received.is_connected(_on_data_received):
		_events.data_received.disconnect(_on_data_received)

	_transport = transport
	_events = events
	_logger = logger
	_state_replicator = state_replicator
	_authority_manager = authority_manager

	if _events and not _events.data_received.is_connected(_on_data_received):
		_events.data_received.connect(_on_data_received)


func send_world_snapshot(target_peer: int) -> void:
	## Collects and sends a full world snapshot to a specific peer.
	var snapshot := _build_world_snapshot()
	_sequence = (_sequence + 1) % 256

	var payload := snapshot
	var data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.WORLD_SNAPSHOT, 0, _sequence, payload
	)

	# Check if we need chunking
	if data.size() > 3000:
		_send_chunked(target_peer, data)
	else:
		_transport.send(target_peer, data, NetworkEnums.ChannelType.CONTROL, true)

	_logger.info("World snapshot sent to peer %d (%d bytes)" % [target_peer, data.size()], "LateJoinHandler")


func _build_world_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}

	# Get entity states from StateReplicator
	if _state_replicator and _state_replicator.has_method("get_full_snapshot"):
		snapshot["replication"] = _state_replicator.get_full_snapshot()

	# Get authority map from AuthorityManager
	if _authority_manager and _authority_manager.has_method("get_authority_map_snapshot"):
		snapshot["authority"] = _authority_manager.get_authority_map_snapshot()

	# Get current scene from SceneSync
	var scene_sync: Node = get_parent().get_node_or_null("SceneSync")
	if scene_sync and scene_sync.has_method("get_current_scene"):
		snapshot["scene"] = scene_sync.get_current_scene()

	return snapshot


func _send_chunked(target_peer: int, data: PackedByteArray) -> void:
	const CHUNK_SIZE := 2048
	var total_chunks := ceili(float(data.size()) / CHUNK_SIZE)

	for i: int in total_chunks:
		var start := i * CHUNK_SIZE
		var end := mini((i + 1) * CHUNK_SIZE, data.size())
		var chunk := data.slice(start, end)

		_sequence = (_sequence + 1) % 256
		var chunk_payload := {
			"chunk_index": i,
			"total_chunks": total_chunks,
			"chunk_data": chunk,
		}
		var chunk_msg := MessageSerializer.serialize_message(
			NetworkEnums.MessageType.WORLD_SNAPSHOT_CHUNK, 0, _sequence, chunk_payload
		)
		_transport.send(target_peer, chunk_msg, NetworkEnums.ChannelType.CONTROL, true)

	_logger.debug("Sent world snapshot in %d chunks" % total_chunks, "LateJoinHandler")


func _on_data_received(from_peer: int, _channel: int, data: PackedByteArray) -> void:
	if data.size() < MessageSerializer.HEADER_SIZE:
		return

	var header := MessageSerializer.deserialize_header(data)
	var msg_type: int = header.get("type", -1)

	match msg_type:
		NetworkEnums.MessageType.WORLD_SNAPSHOT:
			_handle_world_snapshot(from_peer, data)
		NetworkEnums.MessageType.WORLD_SNAPSHOT_CHUNK:
			_handle_world_snapshot_chunk(from_peer, data)


## Chunk reassembly state
var _chunk_buffer: Dictionary = {}  # peer_id -> {chunks: Array, expected: int}


func _handle_world_snapshot(_from_peer: int, data: PackedByteArray) -> void:
	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return

	_apply_world_snapshot(payload)


func _handle_world_snapshot_chunk(from_peer: int, data: PackedByteArray) -> void:
	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return

	var chunk_index: int = payload.get("chunk_index", 0)
	var total_chunks: int = payload.get("total_chunks", 1)
	var chunk_data: PackedByteArray = payload.get("chunk_data", PackedByteArray())
	if total_chunks <= 0 or total_chunks > 512:
		_logger.warn("Invalid world snapshot chunk count from peer %d: %d" % [from_peer, total_chunks], "LateJoinHandler")
		return
	if chunk_index < 0 or chunk_index >= total_chunks:
		_logger.warn("Invalid world snapshot chunk index from peer %d: %d/%d" % [from_peer, chunk_index, total_chunks], "LateJoinHandler")
		return

	if not _chunk_buffer.has(from_peer):
		_chunk_buffer[from_peer] = {"chunks": [], "expected": total_chunks}
		_chunk_buffer[from_peer]["chunks"].resize(total_chunks)
	elif int(_chunk_buffer[from_peer].get("expected", total_chunks)) != total_chunks:
		_chunk_buffer.erase(from_peer)
		_chunk_buffer[from_peer] = {"chunks": [], "expected": total_chunks}
		_chunk_buffer[from_peer]["chunks"].resize(total_chunks)

	_chunk_buffer[from_peer]["chunks"][chunk_index] = chunk_data

	# Check if all chunks received
	var all_received := true
	for c: Variant in _chunk_buffer[from_peer]["chunks"]:
		if c == null:
			all_received = false
			break

	if all_received:
		# Reassemble
		var full_data := PackedByteArray()
		for c: PackedByteArray in _chunk_buffer[from_peer]["chunks"]:
			full_data.append_array(c)
		_chunk_buffer.erase(from_peer)

		# Deserialize the reassembled data as a world snapshot
		if full_data.size() < MessageSerializer.HEADER_SIZE:
			return
		var snapshot: Variant = MessageSerializer.deserialize_payload(full_data)
		if snapshot is Dictionary:
			_apply_world_snapshot(snapshot)

		# Send ACK
		_sequence = (_sequence + 1) % 256
		var ack := MessageSerializer.serialize_message(
			NetworkEnums.MessageType.WORLD_SNAPSHOT_ACK, 0, _sequence, {}
		)
		_transport.send(from_peer, ack, NetworkEnums.ChannelType.CONTROL, true)


func _apply_world_snapshot(snapshot: Dictionary) -> void:
	_logger.info("Applying world snapshot", "LateJoinHandler")

	# Apply replication state
	var replication: Dictionary = snapshot.get("replication", {})
	if not replication.is_empty() and _state_replicator and _state_replicator.has_method("apply_full_snapshot"):
		_state_replicator.apply_full_snapshot(replication)

	# Apply authority map
	var authority: Dictionary = snapshot.get("authority", {})
	if not authority.is_empty() and _authority_manager and _authority_manager.has_method("apply_authority_map"):
		_authority_manager.apply_authority_map(authority)

	# Notify scene sync
	var scene_path: String = snapshot.get("scene", "")
	if scene_path != "":
		_logger.info("Late join: scene is %s" % scene_path, "LateJoinHandler")
