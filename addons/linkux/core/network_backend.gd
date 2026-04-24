class_name NetworkBackend
extends Node
## Abstract base class defining the contract that all backends MUST implement.
## Every virtual method prefixed with _backend_ must be overridden by concrete backends.

# ── Signals (backends MUST emit these) ───────────────────────────────────────

signal backend_peer_connected(peer_id: int)
signal backend_peer_disconnected(peer_id: int, reason: int)
signal backend_connection_succeeded()
signal backend_connection_failed(error: String)
signal backend_session_created(session_info: SessionInfo)
signal backend_data_received(from_peer: int, channel: int, data: PackedByteArray)


# ── Lifecycle ────────────────────────────────────────────────────────────────

func _backend_initialize(config: Resource) -> Error:
	push_error("LinkUx: _backend_initialize() not implemented in %s" % get_class())
	return ERR_UNAVAILABLE


func _backend_shutdown() -> void:
	push_error("LinkUx: _backend_shutdown() not implemented in %s" % get_class())


# ── Session Management ───────────────────────────────────────────────────────

func _backend_create_session(session_name: String, max_players: int, metadata: Dictionary) -> Error:
	push_error("LinkUx: _backend_create_session() not implemented in %s" % get_class())
	return ERR_UNAVAILABLE


func _backend_join_session(session_info: SessionInfo) -> Error:
	push_error("LinkUx: _backend_join_session() not implemented in %s" % get_class())
	return ERR_UNAVAILABLE


func _backend_close_session() -> void:
	push_error("LinkUx: _backend_close_session() not implemented in %s" % get_class())


func _backend_join_session_by_room_code(room_code: String) -> Error:
	push_error("LinkUx: _backend_join_session_by_room_code() not implemented in %s" % get_class())
	return ERR_UNAVAILABLE


# ── Data Transport ───────────────────────────────────────────────────────────

func _backend_send(peer_id: int, data: PackedByteArray, channel: int, reliable: bool) -> Error:
	push_error("LinkUx: _backend_send() not implemented in %s" % get_class())
	return ERR_UNAVAILABLE


func _backend_poll() -> void:
	pass


# ── Peer Info ────────────────────────────────────────────────────────────────

func _backend_get_local_peer_id() -> int:
	push_error("LinkUx: _backend_get_local_peer_id() not implemented in %s" % get_class())
	return -1


func _backend_is_host() -> bool:
	push_error("LinkUx: _backend_is_host() not implemented in %s" % get_class())
	return false


func _backend_get_connected_peers() -> Array[int]:
	push_error("LinkUx: _backend_get_connected_peers() not implemented in %s" % get_class())
	return []


func _backend_get_peer_rtt(peer_id: int) -> float:
	return -1.0


# ── Godot Integration ────────────────────────────────────────────────────────

func _backend_get_multiplayer_peer() -> MultiplayerPeer:
	return null


# ── Capabilities ─────────────────────────────────────────────────────────────

func _backend_get_capabilities() -> Dictionary:
	return {
		"supports_late_join": true,
		"supports_authority_transfer": true,
		"supports_interest_management": true,
		"supports_compression": true,
		"supports_secure_connection": false,
		"max_packet_size": 4096,
		## Si true, los broadcasts desde un cliente no llegan a otros clientes; el host debe reenviar STATE_*.
		"host_relays_client_state": false,
	}


func _backend_validate_peer_identity(peer_id: int) -> bool:
	return peer_id > 0


# ── Peer Management ──────────────────────────────────────────────────────────

func _backend_kick_peer(peer_id: int, reason: String = "") -> void:
	## Override in backends that support kicking peers.
	pass
