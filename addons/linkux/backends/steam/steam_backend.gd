class_name SteamBackend
extends NetworkBackend
## Steam backend using GodotSteam's SteamMultiplayerPeer + Steam Lobbies for matchmaking.
## Room codes are 6-character alphanumeric strings stored as lobby metadata.
## Fully encapsulates Steam API — no Steam calls are exposed to the user.

var _peer: SteamMultiplayerPeer
var _config: SteamBackendConfig
var _is_host: bool = false
var _local_peer_id: int = -1
var _connected_peers: Array[int] = []

var _session_info: SessionInfo

## Steam lobby ID for the current session.
var _lobby_id: int = 0
## 6-char room code set/found by this backend.
var _room_code: String = ""

## Pending host session data stored while waiting for lobby_created callback.
var _pending_session_name: String = ""
var _pending_max_players: int = 0
var _pending_metadata: Dictionary = {}

## True after client SteamMultiplayerPeer reports CONNECTED.
var _client_session_ready_emitted: bool = false
## True while waiting for lobby search or Steam connection to complete.
var _client_connect_pending: bool = false
var _client_connect_started_msec: int = -1
## Kick reason string received via notice packet before the host disconnects us.
var _pending_kick_message: String = ""

## Steam signals connected? Tracked so shutdown can safely disconnect them.
var _steam_signals_connected: bool = false
## Guards the call_deferred emit of backend_connection_succeeded so it is cancelled if the
## backend is shut down between the detection frame and the deferred fire frame.
var _connection_succeeded_pending: bool = false

## Kick notice packet: 2-byte magic "LK" (LinkUx Kick) — same protocol as LAN backend.
const _KICK_MAGIC_0: int = 0x4C  # 'L'
const _KICK_MAGIC_1: int = 0x4B  # 'K'
const _KICK_MSG_DEFAULT: String = "You were kicked from the session."

const _ROOM_CODE_CHARS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const _ROOM_CODE_LENGTH: int = 6

## Lobby metadata keys used to identify LinkUx lobbies.
const _LOBBY_KEY_ROOM_CODE: String = "linkux_room_code"
const _LOBBY_KEY_BACKEND: String = "linkux_backend"
const _LOBBY_VAL_BACKEND: String = "steam_v1"


func _backend_initialize(config: Resource) -> Error:
	if config is SteamBackendConfig:
		_config = config as SteamBackendConfig
	else:
		_config = SteamBackendConfig.new()
	_connect_steam_signals()
	return OK


func _backend_shutdown() -> void:
	_disconnect_steam_signals()
	_close_peer()


func _exit_tree() -> void:
	## Safety net: if queue_free() fires before _backend_shutdown() was called explicitly,
	## ensure signals are disconnected so they don't reach a freed object.
	_disconnect_steam_signals()
	_close_peer()


func _backend_create_session(session_name: String, max_players: int, metadata: Dictionary) -> Error:
	_close_peer()
	_is_host = true
	_pending_session_name = session_name
	_pending_max_players = maxi(1, max_players)
	_pending_metadata = metadata.duplicate()
	var lobby_type: int = _config.lobby_type
	if _is_private_session_meta(metadata):
		lobby_type = 3  # LOBBY_TYPE_INVISIBLE
	Steam.createLobby(lobby_type, _pending_max_players)
	return OK


func _backend_join_session(session_info: SessionInfo) -> Error:
	_close_peer()
	var lobby_id: int = int(session_info.backend_data.get("lobby_id", 0))
	if lobby_id == 0:
		return ERR_INVALID_PARAMETER
	_session_info = session_info
	_is_host = false
	_client_connect_pending = true
	_client_connect_started_msec = Time.get_ticks_msec()
	_room_code = session_info.backend_data.get("room_code", "")
	Steam.joinLobby(lobby_id)
	return OK


func _backend_join_session_by_room_code(room_code: String) -> Error:
	var code := room_code.strip_edges().to_upper()
	if not _is_valid_room_code(code):
		return ERR_INVALID_PARAMETER
	_close_peer()
	_is_host = false
	_room_code = code
	_client_connect_pending = true
	_client_connect_started_msec = Time.get_ticks_msec()
	## Filter lobbies by room code and backend identifier, then request the list.
	Steam.addRequestLobbyListStringFilter(_LOBBY_KEY_ROOM_CODE, code, 0)   # 0 = LOBBY_COMPARISON_EQUAL
	Steam.addRequestLobbyListStringFilter(_LOBBY_KEY_BACKEND, _LOBBY_VAL_BACKEND, 0)
	Steam.requestLobbyList()
	return OK


func _backend_close_session() -> void:
	if _lobby_id != 0:
		Steam.leaveLobby(_lobby_id)
		_lobby_id = 0
	_close_peer()
	_is_host = false
	_local_peer_id = -1
	_connected_peers.clear()
	_session_info = null
	_room_code = ""


func _backend_kick_peer(peer_id: int, reason: String = "") -> void:
	if not _is_host:
		return
	var msg := reason if not reason.is_empty() else _KICK_MSG_DEFAULT
	## Send kick notice before disconnecting so the client can read the reason.
	var notice := PackedByteArray([_KICK_MAGIC_0, _KICK_MAGIC_1]) + msg.to_utf8_buffer()
	_backend_send(peer_id, notice, 0, true)
	if _peer:
		_peer.disconnect_peer(peer_id, true)


func _backend_send(peer_id: int, data: PackedByteArray, channel: int, reliable: bool) -> Error:
	if _peer == null:
		return ERR_UNCONFIGURED

	var transfer_mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable \
		else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE

	_peer.set_target_peer(peer_id)
	_peer.set_transfer_channel(channel)
	_peer.set_transfer_mode(transfer_mode)
	_peer.put_packet(data)
	return OK


func _backend_poll() -> void:
	## Steam callbacks must be pumped manually; embed_callbacks is disabled in this project.
	Steam.run_callbacks()

	if _peer == null:
		return

	## Client-side connect timeout: fail fast if Steam stays CONNECTING too long.
	if not _is_host and _client_connect_pending and not _client_session_ready_emitted:
		if _client_connect_started_msec >= 0:
			var timeout_ms: int = int(maxf(1.0, float(_config.connection_timeout)) * 1000.0)
			if Time.get_ticks_msec() - _client_connect_started_msec > timeout_ms:
				_client_connect_pending = false
				_client_connect_started_msec = -1
				_close_peer()
				backend_connection_failed.emit("Connection timed out. Could not reach the Steam host.")
				return

	var st: int = _peer.get_connection_status()

	if st == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if not _is_host:
			if _client_connect_pending:
				_client_connect_pending = false
				_client_connect_started_msec = -1
				_close_peer()
				backend_connection_failed.emit("Could not connect. The session may be full, closed, or refusing connections.")
			elif _client_session_ready_emitted:
				_client_session_ready_emitted = false
				_local_peer_id = -1
				_connected_peers.clear()
				var msg := _pending_kick_message if not _pending_kick_message.is_empty() \
					else "The host closed the session or disconnected."
				_close_peer()
				backend_connection_failed.emit(msg)
		return

	_peer.poll()
	_sync_multiplayer_peer_lists()

	while _peer.get_available_packet_count() > 0:
		var from_peer: int = _peer.get_packet_peer()
		var channel: int = _peer.get_packet_channel()
		var packet: PackedByteArray = _peer.get_packet()
		## Kick notice: starts with 2-byte magic "LK", followed by a UTF-8 reason string.
		if packet.size() >= 2 and packet[0] == _KICK_MAGIC_0 and packet[1] == _KICK_MAGIC_1:
			_pending_kick_message = PackedByteArray(packet.slice(2)).get_string_from_utf8()
			continue
		backend_data_received.emit(from_peer, channel, packet)


func _backend_get_local_peer_id() -> int:
	if _peer:
		return multiplayer.get_unique_id()
	return _local_peer_id


func _backend_is_host() -> bool:
	return _is_host


func _backend_get_connected_peers() -> Array[int]:
	return _connected_peers.duplicate()


func _backend_get_peer_rtt(_peer_id: int) -> float:
	## Steam networking doesn't expose per-peer RTT through SteamMultiplayerPeer easily.
	return -1.0


func _backend_get_multiplayer_peer() -> MultiplayerPeer:
	return _peer


func _backend_get_capabilities() -> Dictionary:
	return {
		"supports_late_join": true,
		"supports_authority_transfer": true,
		"supports_interest_management": true,
		"supports_compression": false,   # Steam's networking layer handles compression internally.
		"supports_secure_connection": true,
		"max_packet_size": 512000,
		"host_relays_client_state": true,
	}


func _backend_validate_peer_identity(peer_id: int) -> bool:
	return peer_id in _connected_peers or peer_id == _local_peer_id


# ── Steam signal handlers ─────────────────────────────────────────────────────

func _on_lobby_created(connect: int, lobby_id: int) -> void:
	if connect != 1:  # 1 = k_EResultOK
		_is_host = false
		backend_connection_failed.emit("Failed to create Steam lobby (result %d)." % connect)
		return

	_lobby_id = lobby_id
	_room_code = _generate_room_code()

	Steam.setLobbyData(lobby_id, _LOBBY_KEY_ROOM_CODE, _room_code)
	Steam.setLobbyData(lobby_id, _LOBBY_KEY_BACKEND, _LOBBY_VAL_BACKEND)

	_peer = SteamMultiplayerPeer.new()
	var err: Error = _peer.create_host(0)
	if err != OK:
		_close_peer()
		Steam.leaveLobby(lobby_id)
		_lobby_id = 0
		_is_host = false
		backend_connection_failed.emit("Failed to create SteamMultiplayerPeer host (error %d)." % err)
		return

	multiplayer.multiplayer_peer = _peer
	_local_peer_id = 1
	_connected_peers.clear()
	_client_session_ready_emitted = false
	_client_connect_pending = false

	_session_info = SessionInfo.new()
	_session_info.session_id = "steam_%d" % _lobby_id
	_session_info.session_name = _pending_session_name
	_session_info.host_peer_id = 1
	_session_info.max_players = _pending_max_players
	_session_info.current_players = 1
	_session_info.room_code = _room_code
	_session_info.metadata = _pending_metadata
	_session_info.metadata["room_code"] = _room_code
	_session_info.backend_data = {
		"lobby_id": _lobby_id,
		"room_code": _room_code,
		"backend_type": NetworkEnums.BackendType.STEAM,
	}

	backend_session_created.emit(_session_info)

	if _is_private_session():
		_peer.refuse_new_connections = true


func _on_lobby_match_list(lobbies: Array) -> void:
	if lobbies.is_empty():
		_client_connect_pending = false
		_client_connect_started_msec = -1
		backend_connection_failed.emit("No lobby found with room code \"%s\"." % _room_code)
		return
	## Join the first matching lobby.
	Steam.joinLobby(int(lobbies[0]))


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	## Steam emits lobby_joined for the host too after createLobby — ignore it on our end.
	if _is_host:
		return
	if response != 1:  # 1 = k_EChatRoomEnterResponseSuccess
		_client_connect_pending = false
		_client_connect_started_msec = -1
		backend_connection_failed.emit("Failed to join Steam lobby (response %d)." % response)
		return

	_lobby_id = lobby_id

	var host_steam_id: int = Steam.getLobbyOwner(lobby_id)
	if host_steam_id == 0:
		_client_connect_pending = false
		_client_connect_started_msec = -1
		backend_connection_failed.emit("Could not retrieve host Steam ID from lobby.")
		return

	## Steam P2P does not support connections between two instances sharing the same Steam ID.
	## This happens when testing host + client on the same machine with the same account.
	if host_steam_id == Steam.getSteamID():
		_client_connect_pending = false
		_client_connect_started_msec = -1
		Steam.leaveLobby(lobby_id)
		_lobby_id = 0
		backend_connection_failed.emit(
			"Cannot connect: host and client share the same Steam ID. " +
			"Test with two different Steam accounts or two different machines."
		)
		return

	_peer = SteamMultiplayerPeer.new()
	var err: Error = _peer.create_client(host_steam_id, 0)
	if err != OK:
		_close_peer()
		Steam.leaveLobby(lobby_id)
		_lobby_id = 0
		_client_connect_pending = false
		backend_connection_failed.emit("Failed to create SteamMultiplayerPeer client (error %d)." % err)
		return

	multiplayer.multiplayer_peer = _peer

	if _session_info == null:
		_session_info = SessionInfo.new()
	_session_info.session_id = "steam_%d" % lobby_id
	_session_info.room_code = _room_code
	_session_info.backend_data = {
		"lobby_id": lobby_id,
		"room_code": _room_code,
		"backend_type": NetworkEnums.BackendType.STEAM,
	}


# ── Internal ──────────────────────────────────────────────────────────────────

func _close_peer() -> void:
	_connection_succeeded_pending = false
	if _peer:
		_peer.close()
		multiplayer.multiplayer_peer = null
		_peer = null
	_client_session_ready_emitted = false
	_client_connect_pending = false
	_client_connect_started_msec = -1
	_pending_kick_message = ""


func _deferred_emit_connection_succeeded() -> void:
	if not _connection_succeeded_pending:
		return
	_connection_succeeded_pending = false
	backend_connection_succeeded.emit()


func _sync_multiplayer_peer_lists() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var mp_peers: PackedInt32Array = multiplayer.get_peers()
	var current: Array[int] = []
	for i: int in range(mp_peers.size()):
		current.append(mp_peers[i])

	if not _is_host:
		if _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			if not _client_session_ready_emitted:
				_client_session_ready_emitted = true
				_client_connect_pending = false
				_client_connect_started_msec = -1
				_local_peer_id = _peer.get_unique_id()
				## Defer one frame: SteamMultiplayerPeer reports CONNECTION_CONNECTED before it
				## finishes registering peer 1 in its send table. Without the defer, LinkUx's
				## protocol handshake fires immediately and gets "Invalid target peer: 1".
				_connection_succeeded_pending = true
				_deferred_emit_connection_succeeded.call_deferred()
		elif _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			pass
		else:
			return

	_diff_emit_peer_changes(current)


func _diff_emit_peer_changes(current: Array[int]) -> void:
	for pid: int in current:
		if pid not in _connected_peers:
			_connected_peers.append(pid)
			backend_peer_connected.emit(pid)
			if _peer and _session_info and _connected_peers.size() >= (_session_info.max_players - 1):
				_peer.refuse_new_connections = true
	var to_remove: Array[int] = []
	for pid: int in _connected_peers:
		if pid not in current:
			to_remove.append(pid)
	for pid: int in to_remove:
		_connected_peers.erase(pid)
		backend_peer_disconnected.emit(pid, NetworkEnums.DisconnectReason.GRACEFUL)
		if _peer and not _is_private_session() and _session_info \
				and _connected_peers.size() < (_session_info.max_players - 1):
			_peer.refuse_new_connections = false


func _is_private_session() -> bool:
	if _session_info == null:
		return false
	return bool(_session_info.metadata.get("private", false))


func _is_private_session_meta(metadata: Dictionary) -> bool:
	return bool(metadata.get("private", false))


func _generate_room_code() -> String:
	var code := ""
	for _i: int in range(_ROOM_CODE_LENGTH):
		code += _ROOM_CODE_CHARS[randi() % _ROOM_CODE_CHARS.length()]
	return code


func _is_valid_room_code(code: String) -> bool:
	if code.length() != _ROOM_CODE_LENGTH:
		return false
	for i: int in range(code.length()):
		if _ROOM_CODE_CHARS.find(code[i]) < 0:
			return false
	return true


func _connect_steam_signals() -> void:
	if _steam_signals_connected:
		return
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_joined.connect(_on_lobby_joined)
	_steam_signals_connected = true


func _disconnect_steam_signals() -> void:
	if not _steam_signals_connected:
		return
	if Steam.lobby_created.is_connected(_on_lobby_created):
		Steam.lobby_created.disconnect(_on_lobby_created)
	if Steam.lobby_match_list.is_connected(_on_lobby_match_list):
		Steam.lobby_match_list.disconnect(_on_lobby_match_list)
	if Steam.lobby_joined.is_connected(_on_lobby_joined):
		Steam.lobby_joined.disconnect(_on_lobby_joined)
	_steam_signals_connected = false
