class_name SessionManager
extends Node
## Manages session lifecycle: create, join, close.
## Delegates transport to the active backend and emits unified events.

enum SessionState {
	IDLE,
	CREATING,
	JOINING,
	IN_SESSION,
	CLOSING,
}

var _state: int = SessionState.IDLE
var _backend: NetworkBackend
var _events: NetworkEvents
var _logger: DebugLogger
var _peer_map: PeerIdentityMap
var _current_session: SessionInfo
var _pending_disconnect_confirm: Dictionary = {}  # peer_id -> reason
var _pending_peers: Dictionary = {}              # peer_id -> PlayerInfo (waiting for name handshake)


func setup(backend: NetworkBackend, events: NetworkEvents, logger: DebugLogger, peer_map: PeerIdentityMap) -> void:
	_backend = backend
	_events = events
	_logger = logger
	_peer_map = peer_map
	_connect_backend_signals()


func update_backend(backend: NetworkBackend) -> void:
	_disconnect_backend_signals()
	_backend = backend
	_connect_backend_signals()


func create_session(session_name: String, max_players: int, metadata: Dictionary) -> int:
	if _state != SessionState.IDLE:
		_logger.warn("Cannot create session — state is %d" % _state, "SessionManager")
		return NetworkEnums.ErrorCode.ALREADY_IN_SESSION

	_state = SessionState.CREATING
	_logger.info("Creating session '%s' (max %d)" % [session_name, max_players], "SessionManager")

	var err := _backend._backend_create_session(session_name, max_players, metadata)
	if err != OK:
		# If the backend already emitted backend_connection_failed, the signal handler
		# already reset _state to IDLE and logged the real error — avoid a duplicate log.
		if _state == SessionState.CREATING:
			_state = SessionState.IDLE
			_logger.error("Backend failed to create session: %d" % err, "SessionManager")
		return NetworkEnums.ErrorCode.NETWORK_UNAVAILABLE

	return NetworkEnums.ErrorCode.SUCCESS


func join_session(session_info: SessionInfo) -> int:
	if _state != SessionState.IDLE:
		_logger.warn("Cannot join session — state is %d" % _state, "SessionManager")
		return NetworkEnums.ErrorCode.ALREADY_IN_SESSION

	_state = SessionState.JOINING
	_logger.info("Joining session '%s'" % session_info.session_name, "SessionManager")

	# Preserve the session_info while the backend connects (needed for room_code/metadata).
	_current_session = session_info
	var err := _backend._backend_join_session(session_info)
	if err != OK:
		_current_session = null
		_state = SessionState.IDLE
		_logger.error("Backend failed to join session: %d" % err, "SessionManager")
		return NetworkEnums.ErrorCode.SESSION_NOT_FOUND

	return NetworkEnums.ErrorCode.SUCCESS


func close_session(emit_closed_event: bool = true) -> void:
	if _state == SessionState.IDLE:
		return

	_state = SessionState.CLOSING
	_logger.info("Closing session", "SessionManager")
	_backend._backend_close_session()
	_current_session = null
	_pending_peers.clear()
	_pending_disconnect_confirm.clear()
	_state = SessionState.IDLE
	if emit_closed_event:
		_events.session_closed.emit()


func join_session_by_room_code(room_code: String) -> int:
	var key := room_code.strip_edges().to_upper()
	if key.is_empty():
		return NetworkEnums.ErrorCode.SESSION_NOT_FOUND
	_state = SessionState.JOINING

	# Preserve room_code so it's available in _current_session after connection succeeds.
	# join_session() does this via session_info param; here we create a stub with the code.
	var pending_info := SessionInfo.new()
	pending_info.room_code = key
	pending_info.session_id = "room_%s" % key
	pending_info.session_name = "Room %s" % key
	_current_session = pending_info

	_logger.info("Joining session by room code '%s'" % key, "SessionManager")
	var err := _backend._backend_join_session_by_room_code(key)
	if err != OK:
		_current_session = null
		_state = SessionState.IDLE
		_logger.error("Backend failed to join by room code: %d" % err, "SessionManager")
		return NetworkEnums.ErrorCode.SESSION_NOT_FOUND
	return NetworkEnums.ErrorCode.SUCCESS


func get_current_session() -> SessionInfo:
	return _current_session


func get_state() -> int:
	return _state


## Called by LinkUx when the "linkux_player_name" RPC arrives from a remote peer.
## Completes the pending handshake and emits player_joined with the real display name.
func register_player_name(from_peer: int, name: String) -> void:
	if not _pending_peers.has(from_peer):
		return
	_pending_peers[from_peer].display_name = name
	_flush_pending_peer(from_peer)


func _flush_pending_peer(peer_id: int) -> void:
	if not _pending_peers.has(peer_id):
		return
	var info: PlayerInfo = _pending_peers[peer_id]
	_pending_peers.erase(peer_id)
	_logger.info("Peer joined: %d (%s)" % [peer_id, info.display_name], "SessionManager")
	_events.player_joined.emit(info)


# ── Backend Signal Handlers ──────────────────────────────────────────────────

func _connect_backend_signals() -> void:
	if _backend == null:
		return
	if not _backend.backend_session_created.is_connected(_on_backend_session_created):
		_backend.backend_session_created.connect(_on_backend_session_created)
	if not _backend.backend_connection_succeeded.is_connected(_on_backend_connection_succeeded):
		_backend.backend_connection_succeeded.connect(_on_backend_connection_succeeded)
	if not _backend.backend_connection_failed.is_connected(_on_backend_connection_failed):
		_backend.backend_connection_failed.connect(_on_backend_connection_failed)
	if not _backend.backend_peer_connected.is_connected(_on_backend_peer_connected):
		_backend.backend_peer_connected.connect(_on_backend_peer_connected)
	if not _backend.backend_peer_disconnected.is_connected(_on_backend_peer_disconnected):
		_backend.backend_peer_disconnected.connect(_on_backend_peer_disconnected)


func _disconnect_backend_signals() -> void:
	if _backend == null:
		return
	if _backend.backend_session_created.is_connected(_on_backend_session_created):
		_backend.backend_session_created.disconnect(_on_backend_session_created)
	if _backend.backend_connection_succeeded.is_connected(_on_backend_connection_succeeded):
		_backend.backend_connection_succeeded.disconnect(_on_backend_connection_succeeded)
	if _backend.backend_connection_failed.is_connected(_on_backend_connection_failed):
		_backend.backend_connection_failed.disconnect(_on_backend_connection_failed)
	if _backend.backend_peer_connected.is_connected(_on_backend_peer_connected):
		_backend.backend_peer_connected.disconnect(_on_backend_peer_connected)
	if _backend.backend_peer_disconnected.is_connected(_on_backend_peer_disconnected):
		_backend.backend_peer_disconnected.disconnect(_on_backend_peer_disconnected)


func _on_backend_session_created(info: SessionInfo) -> void:
	_current_session = info
	_state = SessionState.IN_SESSION

	# Register host in identity map
	var local_id := _backend._backend_get_local_peer_id()
	_peer_map.register_host(str(local_id))

	var host_info := PlayerInfo.new()
	host_info.peer_id = local_id
	host_info.display_name = info.session_name if not info.session_name.is_empty() else "Host"
	host_info.is_host = true

	_logger.info("Session created: %s" % info.session_name, "SessionManager")
	_events.session_created.emit(info)
	_events.player_joined.emit(host_info)


func _on_backend_connection_succeeded() -> void:
	_state = SessionState.IN_SESSION
	var local_id := _backend._backend_get_local_peer_id()
	_peer_map.register_peer_with_id(local_id, str(local_id))

	if _current_session == null:
		_current_session = SessionInfo.new()
		_current_session.session_id = "joined_session"

	_logger.info("Connected to session (local peer: %d)" % local_id, "SessionManager")
	_events.session_joined.emit(_current_session)


func _on_backend_connection_failed(error: String) -> void:
	var was_in_session: bool = (_state == SessionState.IN_SESSION)
	if _backend:
		_backend._backend_close_session()
	_current_session = null
	_state = SessionState.IDLE
	_logger.error("Connection failed: %s" % error, "SessionManager")
	if was_in_session:
		_events.session_closed.emit()
	_events.connection_failed.emit(error)


func _on_backend_peer_connected(peer_id: int) -> void:
	# Cancel any pending graceful-disconnect confirmation for this peer so the
	# 0.2s timer doesn't fire after we process this new connection.
	_pending_disconnect_confirm.erase(peer_id)
	_peer_map.register_peer_with_id(peer_id, str(peer_id))

	var info := PlayerInfo.new()
	info.peer_id = peer_id
	info.display_name = "Peer_%d" % peer_id  # placeholder until name handshake completes
	info.is_host = false

	if _current_session:
		if peer_id in _current_session.connected_peers:
			# Fast reconnect: the client disconnected and reconnected before the 0.2s
			# confirmation timer fired. The peer is still listed as "connected" in the
			# session, so we must flush the old state first — otherwise subsystems
			# (SceneSync, DisconnectHandler, Spawner) never receive peer_connected and
			# the client ends up stuck with no SCENE_LOAD_REQUEST.
			_logger.info("Fast reconnect detected for peer %d — flushing old state" % peer_id, "SessionManager")
			_pending_peers.erase(peer_id)
			_current_session.connected_peers.erase(peer_id)
			_current_session.current_players = maxi(0, _current_session.current_players - 1)
			_peer_map.unregister_peer(peer_id)
			_events.player_left.emit(peer_id, NetworkEnums.DisconnectReason.GRACEFUL)
			_events.peer_disconnected.emit(peer_id, NetworkEnums.DisconnectReason.GRACEFUL)
		_current_session.connected_peers.append(peer_id)
		_current_session.current_players += 1

	_logger.info("Peer connected: %d — waiting for name handshake" % peer_id, "SessionManager")

	# Emit peer_connected immediately so subsystems (transport, heartbeat) can route packets.
	# Delay player_joined until the client sends their display name via RPC.
	_pending_peers[peer_id] = info
	_events.peer_connected.emit(peer_id)

	# Timeout: if name RPC never arrives, flush with placeholder so the game isn't left hanging.
	get_tree().create_timer(0.5).timeout.connect(
		func() -> void: _flush_pending_peer(peer_id), CONNECT_ONE_SHOT
	)


func _on_backend_peer_disconnected(peer_id: int, reason: int) -> void:
	# ENet can report transient peer-list changes during churn (fast leave/join).
	# Confirm on the next frame with a short delay before emitting player_left to avoid despawning the wrong peer.
	_pending_disconnect_confirm[peer_id] = reason
	var tr := get_tree().create_timer(0.2)
	tr.timeout.connect(_confirm_backend_peer_disconnected.bind(peer_id), CONNECT_ONE_SHOT)


func _confirm_backend_peer_disconnected(peer_id: int) -> void:
	if not _pending_disconnect_confirm.has(peer_id):
		return
	_pending_peers.erase(peer_id)  # cancel handshake if peer disconnects before name arrives
	if _backend and peer_id in _backend._backend_get_connected_peers():
		# Evento transitorio: el peer sigue conectado.
		_pending_disconnect_confirm.erase(peer_id)
		return
	var reason: int = int(_pending_disconnect_confirm.get(peer_id, NetworkEnums.DisconnectReason.GRACEFUL))
	_pending_disconnect_confirm.erase(peer_id)
	_peer_map.unregister_peer(peer_id)

	# Session was closed before this deferred callback fired — nothing left to clean up.
	if _current_session == null or _state == SessionState.IDLE:
		return

	if peer_id in _current_session.connected_peers:
		_current_session.connected_peers.erase(peer_id)
		_current_session.current_players = maxi(0, _current_session.current_players - 1)
	else:
		_logger.debug("Ignoring duplicate peer_disconnected for %d" % peer_id, "SessionManager")
		return

	_logger.info("Peer disconnected: %d (reason: %d)" % [peer_id, reason], "SessionManager")
	_events.player_left.emit(peer_id, reason)
	_events.peer_disconnected.emit(peer_id, reason)
