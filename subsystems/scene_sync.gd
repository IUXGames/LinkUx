class_name SceneSync
extends Node
## Barrier pattern for synchronized scene loading.
## Ensures all peers have fully loaded a scene before gameplay resumes.

signal scene_load_requested(scene_path: String)

enum SyncState {
	IDLE,
	LOADING,
	WAITING,
	READY,
}

var _transport: TransportLayer
var _events: NetworkEvents
var _logger: DebugLogger

var _state: int = SyncState.IDLE
var _current_scene: String = ""
var _ready_peers: Dictionary = {}  # peer_id -> bool
var _sequence: int = 0
var _scene_load_retry: Dictionary = {}  # peer_id -> int (retry generation; 0 = inactive)


func setup(transport: TransportLayer, events: NetworkEvents, logger: DebugLogger) -> void:
	if _events:
		if _events.data_received.is_connected(_on_data_received):
			_events.data_received.disconnect(_on_data_received)
		if _events.peer_disconnected.is_connected(_on_peer_disconnected):
			_events.peer_disconnected.disconnect(_on_peer_disconnected)
		if _events.peer_connected.is_connected(_on_events_peer_connected):
			_events.peer_connected.disconnect(_on_events_peer_connected)

	_transport = transport
	_events = events
	_logger = logger

	if _events:
		if not _events.data_received.is_connected(_on_data_received):
			_events.data_received.connect(_on_data_received)
		if not _events.peer_disconnected.is_connected(_on_peer_disconnected):
			_events.peer_disconnected.connect(_on_peer_disconnected)
		if not _events.peer_connected.is_connected(_on_events_peer_connected):
			_events.peer_connected.connect(_on_events_peer_connected)


func request_scene_load(scene_path: String) -> void:
	## Host only — broadcasts scene load request to all peers.
	_current_scene = scene_path
	_state = SyncState.LOADING
	_ready_peers.clear()

	_sequence = (_sequence + 1) % 256
	var payload := {"scene_path": scene_path}
	var data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.SCENE_LOAD_REQUEST, 0, _sequence, payload
	)
	_transport.broadcast(data, NetworkEnums.ChannelType.CONTROL, true)
	_logger.info("Scene load requested: %s" % scene_path, "SceneSync")

	# Host does not receive its own broadcast over ENet; emit locally so UI/game can load.
	var linkux_host: Node = get_parent()
	if linkux_host and linkux_host.has_method("is_host") and linkux_host.is_host():
		scene_load_requested.emit(scene_path)


func report_scene_ready() -> void:
	## Called by local peer after scene is fully loaded and initialized.
	var linkux: Node = get_parent()
	var local_peer := -1
	if linkux and linkux.has_method("get_local_peer_id"):
		local_peer = linkux.get_local_peer_id()

	if linkux and linkux.has_method("is_host") and linkux.is_host():
		# Host: mark self as ready
		_ready_peers[local_peer] = true
		_state = SyncState.WAITING
		_check_all_ready()
	else:
		# Client: send ready report to host
		_sequence = (_sequence + 1) % 256
		var payload := {"peer_id": local_peer}
		var data := MessageSerializer.serialize_message(
			NetworkEnums.MessageType.SCENE_READY_REPORT, 0, _sequence, payload
		)
		_transport.send(1, data, NetworkEnums.ChannelType.CONTROL, true)
		_state = SyncState.WAITING

	_logger.debug("Scene ready reported by peer %d" % local_peer, "SceneSync")


func get_sync_state() -> int:
	return _state


func get_current_scene() -> String:
	return _current_scene


func is_all_ready() -> bool:
	return _state == SyncState.READY


## Call when closing the session (LinkUx._cleanup_session): clients returning to the menu must forget the previous scene.
func reset_session_sync() -> void:
	_state = SyncState.IDLE
	_current_scene = ""
	_ready_peers.clear()
	_scene_load_retry.clear()


# ── Internal ─────────────────────────────────────────────────────────────────

func _check_all_ready() -> void:
	var linkux: Node = get_parent()
	if linkux == null or not linkux.has_method("get_connected_peers"):
		return

	var peers: Array[int] = linkux.get_connected_peers()
	var local_peer: int = linkux.get_local_peer_id()

	# Check host is ready
	if not _ready_peers.get(local_peer, false):
		return

	# Check all connected peers
	for peer_id: int in peers:
		if not _ready_peers.get(peer_id, false):
			return

	# All ready — broadcast
	_state = SyncState.READY
	_sequence = (_sequence + 1) % 256
	var payload := {"scene_path": _current_scene}
	var data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.SCENE_ALL_READY, 0, _sequence, payload
	)
	_transport.broadcast(data, NetworkEnums.ChannelType.CONTROL, true)
	_events.scene_all_ready.emit(_current_scene)
	_logger.info("All peers ready for scene: %s" % _current_scene, "SceneSync")


func _on_data_received(from_peer: int, _channel: int, data: PackedByteArray) -> void:
	if data.size() < MessageSerializer.HEADER_SIZE:
		return

	var header := MessageSerializer.deserialize_header(data)
	var msg_type: int = header.get("type", -1)

	match msg_type:
		NetworkEnums.MessageType.SCENE_LOAD_REQUEST:
			_handle_load_request(from_peer, data)
		NetworkEnums.MessageType.SCENE_READY_REPORT:
			_handle_ready_report(from_peer, data)
		NetworkEnums.MessageType.SCENE_ALL_READY:
			_handle_all_ready(data)


func _handle_load_request(from_peer: int, data: PackedByteArray) -> void:
	if from_peer != 1:
		return
	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return

	_current_scene = payload.get("scene_path", "")
	_state = SyncState.LOADING
	_ready_peers.clear()
	_logger.info("Scene load request received: %s" % _current_scene, "SceneSync")
	scene_load_requested.emit(_current_scene)


func _on_events_peer_connected(peer_id: int) -> void:
	var linkux: Node = get_parent()
	if linkux == null or not linkux.has_method("is_host") or not linkux.is_host():
		return
	if _state != SyncState.WAITING and _state != SyncState.READY and _state != SyncState.LOADING:
		return
	if _current_scene.is_empty():
		return
	## On the same frame as the ENet connection, `get_peer(id)` may not exist yet: send fails and the client stays on "Joining".
	call_deferred("_deferred_send_scene_load_to_peer", peer_id)
	# Start periodic retry so the message is resent if the client's game drops it
	# (e.g. transition animation active, isTransitioning guard, etc.).
	_start_scene_load_retry(peer_id)


func _deferred_send_scene_load_to_peer(peer_id: int) -> void:
	var linkux: Node = get_parent()
	if linkux == null or not linkux.has_method("is_host") or not linkux.is_host():
		return
	if _state != SyncState.WAITING and _state != SyncState.READY and _state != SyncState.LOADING:
		return
	if _current_scene.is_empty():
		return
	var err: Error = _send_scene_load_unicast(peer_id)
	if err != OK:
		_logger.warn("Scene load unicast failed for peer %d (err %d), retrying…" % [peer_id, err], "SceneSync")
		var tr := get_tree().create_timer(0.12)
		tr.timeout.connect(_retry_scene_load_once.bind(peer_id), CONNECT_ONE_SHOT)


func _retry_scene_load_once(peer_id: int) -> void:
	var err: Error = _send_scene_load_unicast(peer_id)
	if err != OK:
		_logger.warn("Scene load unicast retry failed for peer %d (err %d)" % [peer_id, err], "SceneSync")


# Periodic retry loop — resends SCENE_LOAD_REQUEST every 1.5 s until the peer
# reports SCENE_READY or disconnects.  Uses a generation counter so old timer
# callbacks become no-ops when the retry is cancelled.
func _start_scene_load_retry(peer_id: int) -> void:
	var gen: int = _scene_load_retry.get(peer_id, 0) + 1
	_scene_load_retry[peer_id] = gen
	get_tree().create_timer(1.5).timeout.connect(
		_retry_scene_load_loop.bind(peer_id, gen), CONNECT_ONE_SHOT
	)


func _retry_scene_load_loop(peer_id: int, gen: int) -> void:
	if _scene_load_retry.get(peer_id, 0) != gen:
		return  # cancelled
	if _ready_peers.get(peer_id, false):
		_scene_load_retry.erase(peer_id)
		return
	if _current_scene.is_empty() or (_state != SyncState.WAITING and _state != SyncState.LOADING):
		_scene_load_retry.erase(peer_id)
		return
	_logger.info("Retrying SCENE_LOAD_REQUEST for peer %d (no SCENE_READY_REPORT yet)" % peer_id, "SceneSync")
	_send_scene_load_unicast(peer_id)
	var next_gen: int = gen + 1
	_scene_load_retry[peer_id] = next_gen
	get_tree().create_timer(1.5).timeout.connect(
		_retry_scene_load_loop.bind(peer_id, next_gen), CONNECT_ONE_SHOT
	)


func _stop_scene_load_retry(peer_id: int) -> void:
	_scene_load_retry.erase(peer_id)


## Internal RPC: client is still in the menu and did not receive SCENE_LOAD (e.g. host's first send failed).
func _rpc_host_send_scene_load_to_peer(from_peer: int) -> void:
	var linkux: Node = get_parent()
	if linkux == null or not linkux.has_method("is_host") or not linkux.is_host():
		return
	if _current_scene.is_empty():
		return
	_send_scene_load_unicast(from_peer)


func _send_scene_load_unicast(peer_id: int) -> Error:
	_sequence = (_sequence + 1) % 256
	var payload := {"scene_path": _current_scene}
	var data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.SCENE_LOAD_REQUEST, 0, _sequence, payload
	)
	var err: Error = _transport.send(peer_id, data, NetworkEnums.ChannelType.CONTROL, true)
	if err == OK:
		_logger.debug("Scene load re-sync sent to peer %d: %s" % [peer_id, _current_scene], "SceneSync")
	return err


func _handle_ready_report(from_peer: int, _data: PackedByteArray) -> void:
	## Late join: primero replicar al joiner los jugadores ya existentes (unicast), luego barrier + spawn del nuevo, luego snapshot.
	var host_late_join := false
	var linkux: Node = get_parent()
	if linkux and linkux.has_method("is_host") and linkux.is_host():
		host_late_join = (_state == SyncState.READY)

	if host_late_join and linkux.has_method("replay_late_join_spawns_now"):
		linkux.replay_late_join_spawns_now(from_peer)

	_stop_scene_load_retry(from_peer)
	_ready_peers[from_peer] = true
	_logger.debug("Peer %d reported scene ready" % from_peer, "SceneSync")
	_check_all_ready()

	if host_late_join and linkux.has_method("run_late_join_snapshot_only"):
		linkux.call_deferred("run_late_join_snapshot_only", from_peer)


func _handle_all_ready(data: PackedByteArray) -> void:
	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return

	_current_scene = payload.get("scene_path", _current_scene)
	_state = SyncState.READY
	_events.scene_all_ready.emit(_current_scene)
	_logger.info("Scene all ready confirmed: %s" % _current_scene, "SceneSync")


func _on_peer_disconnected(peer_id: int, _reason: int) -> void:
	_stop_scene_load_retry(peer_id)
	_ready_peers.erase(peer_id)
	if _state == SyncState.WAITING:
		_check_all_ready()
