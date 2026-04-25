class_name LanBackend
extends NetworkBackend
## LAN backend using Godot's ENetMultiplayerPeer.
## Fully encapsulates ENet — no ENet API is exposed to the user.

var _peer: ENetMultiplayerPeer
var _config: LanBackendConfig
var _is_host: bool = false
var _local_peer_id: int = -1
var _connected_peers: Array[int] = []

var _session_info: SessionInfo

## True after client ENet reports CONNECTED (used instead of MultiplayerAPI.connected_to_server).
var _client_session_ready_emitted: bool = false
## After create_client succeeds: detect async failure (server full, rejected, timeout).
var _client_connect_pending: bool = false
var _client_connect_started_msec: int = -1
## Kick reason string received via notice packet before the host disconnects us.
var _pending_kick_message: String = ""

## Kick notice packet: 2-byte magic "LK" (LinkUx Kick) followed by the UTF-8 reason string.
const _KICK_MAGIC_0: int = 0x4C  # 'L'
const _KICK_MAGIC_1: int = 0x4B  # 'K'
const _KICK_MSG_DEFAULT: String = "You were kicked from the session."


func _backend_initialize(config: Resource) -> Error:
	if config is LanBackendConfig:
		_config = config as LanBackendConfig
	else:
		_config = LanBackendConfig.new()
	return OK


func _backend_shutdown() -> void:
	_close_peer()


func _backend_create_session(session_name: String, max_players: int, metadata: Dictionary) -> Error:
	_close_peer()

	## ENet: create_server(..., max_clients, ...) = maximum number of *remote* clients; host does not count.
	## max_players in LinkUx = total human slots (host + clients) → clients = total - 1.
	var total_slots: int = maxi(1, max_players)
	var max_clients: int = maxi(0, total_slots - 1)
	var stride: int = maxi(1, _config.lan_port_stride)
	var max_attempts: int = maxi(1, _config.max_lan_host_attempts)

	## Multiple processes on the same machine cannot share the same ENet port.
	for slot: int in range(max_attempts):
		var game_port: int = _config.default_port + slot * stride

		_peer = ENetMultiplayerPeer.new()
		## Godot/ENet requires max_clients between 1 and 4095. If total_slots == 1, max_clients would be 0
		## (invalid). We use maxi(1, max_clients) to allow server creation.
		## Note: this may allow 1 ENet client even when max_players == 1 (logical vs transport limit).
		## If metadata.private == true, the host kicks remote peers on connect (see _diff_emit_peer_changes).
		_peer.set_bind_ip("*")
		var server_max_clients: int = maxi(1, max_clients)
		var err: Error = _peer.create_server(game_port, server_max_clients, 3, _config.in_bandwidth, _config.out_bandwidth)
		if err != OK:
			_peer = null
			continue

		multiplayer.multiplayer_peer = _peer
		_is_host = true
		_local_peer_id = 1
		_connected_peers.clear()
		_client_session_ready_emitted = false
		_client_connect_pending = false
		_client_connect_started_msec = -1

		_session_info = SessionInfo.new()
		_session_info.session_id = "lan_%d" % game_port
		_session_info.session_name = session_name
		_session_info.host_peer_id = 1
		_session_info.max_players = total_slots
		_session_info.current_players = 1
		var host_ip: String = _resolve_host_ip()
		_session_info.room_code = _build_room_code(host_ip, game_port)
		_session_info.metadata = metadata
		_session_info.metadata["room_code"] = _session_info.room_code
		_session_info.backend_data = {
			"ip": host_ip,
			"port": game_port,
			"room_code": _session_info.room_code,
			"backend_type": NetworkEnums.BackendType.LAN,
		}
		backend_session_created.emit(_session_info)
		# Block connections immediately for private sessions (singleplayer, etc.)
		if _is_private_session():
			_peer.refuse_new_connections = true
		return OK

	var msg := (
		"No free LAN port available (%d slots tried, stride %d, starting at %d). "
		+ "Close other host instances or game windows on this machine."
	) % [max_attempts, stride, _config.default_port]
	backend_connection_failed.emit(msg)
	return FAILED


func _backend_join_session(session_info: SessionInfo) -> Error:
	_close_peer()

	var ip: String = session_info.backend_data.get("ip", "127.0.0.1")
	var port: int = session_info.backend_data.get("port", _config.default_port)

	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, port, 3, _config.in_bandwidth, _config.out_bandwidth)
	if err != OK:
		_peer = null
		backend_connection_failed.emit("Failed to connect to %s:%d (error %d)." % [ip, port, err])
		return err

	multiplayer.multiplayer_peer = _peer
	_is_host = false
	_session_info = session_info
	_client_session_ready_emitted = false
	_client_connect_pending = true
	_client_connect_started_msec = Time.get_ticks_msec()

	return OK


func _backend_close_session() -> void:
	_close_peer()
	_is_host = false
	_local_peer_id = -1
	_connected_peers.clear()
	_session_info = null


func _backend_join_session_by_room_code(room_code: String) -> Error:
	var parsed := _parse_room_code(room_code)
	if not bool(parsed.get("ok", false)):
		return ERR_INVALID_PARAMETER
	var info := SessionInfo.new()
	info.session_id = "%s:%d" % [String(parsed["ip"]), int(parsed["port"])]
	info.session_name = "Room %s" % room_code
	info.room_code = room_code
	info.backend_data = {
		"ip": String(parsed["ip"]),
		"port": int(parsed["port"]),
		"room_code": room_code,
		"backend_type": NetworkEnums.BackendType.LAN,
	}
	return _backend_join_session(info)


func _backend_kick_peer(peer_id: int, reason: String = "") -> void:
	## Public kick: host calls this to remove a specific peer with an optional reason shown to them.
	if not _is_host:
		return
	_kick_peer(peer_id, reason if not reason.is_empty() else _KICK_MSG_DEFAULT)


func _backend_send(peer_id: int, data: PackedByteArray, channel: int, reliable: bool) -> Error:
	if _peer == null:
		return ERR_UNCONFIGURED

	var transfer_mode := ENetPacketPeer.FLAG_RELIABLE if reliable else ENetPacketPeer.FLAG_UNSEQUENCED

	if peer_id == 0:
		# Broadcast to all
		for pid: int in _connected_peers:
			var enet_conn := _peer.get_peer(pid)
			if enet_conn:
				enet_conn.send(channel, data, transfer_mode)
	else:
		var enet_conn := _peer.get_peer(peer_id)
		if enet_conn:
			enet_conn.send(channel, data, transfer_mode)
		else:
			return ERR_DOES_NOT_EXIST

	return OK


func _backend_poll() -> void:
	if _peer == null:
		return
	var st: int = _peer.get_connection_status()

	# Client-side connect timeout: fail fast if ENet stays CONNECTING too long.
	if not _is_host and _client_connect_pending and not _client_session_ready_emitted:
		if _client_connect_started_msec >= 0:
			var timeout_ms: int = int(maxf(0.5, float(_config.connection_timeout)) * 1000.0)
			if Time.get_ticks_msec() - _client_connect_started_msec > timeout_ms:
				_client_connect_pending = false
				_client_connect_started_msec = -1
				_close_peer()
				backend_connection_failed.emit("Connection timed out. No host found at that address or port.")
				return

	if st == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if not _is_host:
			if _client_connect_pending:
				_client_connect_pending = false
				_client_connect_started_msec = -1
				_close_peer()
				backend_connection_failed.emit("Could not connect. The session may be full, closed, or refusing connections.")
			elif _client_session_ready_emitted:
				## Host closed the process or session while client was in game.
				_client_session_ready_emitted = false
				_local_peer_id = -1
				_connected_peers.clear()
				# Drain any packets still in the ENet buffer (e.g. kick notice sent just
				# before the disconnect) before reading _pending_kick_message.
				if _peer:
					_peer.poll()
					while _peer.get_available_packet_count() > 0:
						@warning_ignore("unused_variable")
						var _fp := _peer.get_packet_peer()
						@warning_ignore("unused_variable")
						var _fc := _peer.get_packet_channel()
						var pkt := _peer.get_packet()
						if pkt.size() >= 2 and pkt[0] == _KICK_MAGIC_0 and pkt[1] == _KICK_MAGIC_1:
							_pending_kick_message = PackedByteArray(pkt.slice(2)).get_string_from_utf8()
				var msg := _pending_kick_message if not _pending_kick_message.is_empty() \
					else "The host closed the session or disconnected."
				_close_peer()
				backend_connection_failed.emit(msg)
		return
	# Only poll the ENet peer. Do NOT call MultiplayerAPI.poll(): it tries to decode every packet
	# as Godot high-level RPC; LinkUx uses a custom binary protocol on the same ENet connection.
	_peer.poll()
	_sync_multiplayer_peer_lists()
	## get_packet_peer / get_packet_channel describe the *next* packet read by get_packet().
	## Calling get_packet() first consumes the queue and leaves channel/peer invalid (engine errors).
	while _peer.get_available_packet_count() > 0:
		var from_peer := _peer.get_packet_peer()
		var channel := _peer.get_packet_channel()
		var packet := _peer.get_packet()
		# Kick notice: starts with 2-byte magic "LK", followed by a UTF-8 reason string.
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


func _backend_get_peer_rtt(peer_id: int) -> float:
	if _peer:
		var enet_conn := _peer.get_peer(peer_id)
		if enet_conn:
			return enet_conn.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
	return -1.0


func _backend_get_multiplayer_peer() -> MultiplayerPeer:
	return _peer


func _backend_get_capabilities() -> Dictionary:
	return {
		"supports_late_join": true,
		"supports_authority_transfer": true,
		"supports_interest_management": true,
		"supports_compression": true,
		"supports_secure_connection": false,
		"max_packet_size": 4096,
		"host_relays_client_state": true,
	}


func _backend_validate_peer_identity(peer_id: int) -> bool:
	return peer_id in _connected_peers or peer_id == _local_peer_id


# ── Internal ─────────────────────────────────────────────────────────────────

func _close_peer() -> void:
	if _peer:
		_peer.close()
		multiplayer.multiplayer_peer = null
		_peer = null
	_client_session_ready_emitted = false
	_client_connect_pending = false
	_client_connect_started_msec = -1
	_pending_kick_message = ""


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
				backend_connection_succeeded.emit()
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
			# Close the door when session reaches capacity
			if _peer and _session_info and _connected_peers.size() >= (_session_info.max_players - 1):
				_peer.refuse_new_connections = true
	var to_remove: Array[int] = []
	for pid: int in _connected_peers:
		if pid not in current:
			to_remove.append(pid)
	for pid: int in to_remove:
		_connected_peers.erase(pid)
		backend_peer_disconnected.emit(pid, NetworkEnums.DisconnectReason.GRACEFUL)
		# Re-open connections when a slot becomes available (never for private sessions)
		if _peer and not _is_private_session() and _session_info \
				and _connected_peers.size() < (_session_info.max_players - 1):
			_peer.refuse_new_connections = false


func _is_private_session() -> bool:
	if _session_info == null:
		return false
	return bool(_session_info.metadata.get("private", false))


func _kick_peer(peer_id: int, reason_msg: String = "") -> void:
	if _peer == null or peer_id == 1:
		return
	var enet_peer := _peer.get_peer(peer_id)
	if enet_peer:
		# Send reason notice before disconnecting. peer_disconnect() (graceful) flushes
		# the reliable send queue before closing, ensuring the notice packet arrives.
		var notice := PackedByteArray([_KICK_MAGIC_0, _KICK_MAGIC_1]) + reason_msg.to_utf8_buffer()
		enet_peer.send(0, notice, ENetPacketPeer.FLAG_RELIABLE)
		enet_peer.peer_disconnect()


func _build_room_code(ip: String, _port: int) -> String:
	# LAN room code: 8 uppercase hex digits = full IPv4 address (32 bits).
	# e.g. 192.168.1.1 → "C0A80101"
	# Port is not encoded; clients always connect to _config.default_port.
	var ip_u32 := _ipv4_to_u32(ip)
	if ip_u32 < 0:
		ip_u32 = _ipv4_to_u32("127.0.0.1")
	return "%08X" % (ip_u32 & 0xFFFFFFFF)


func _parse_room_code(room_code: String) -> Dictionary:
	var code := room_code.strip_edges().to_upper()

	# Back-compat: old verbose format LAN-<ip-with-dashes>-<port>
	if code.begins_with("LAN-"):
		var raw := code.substr(4)
		var parts: Array = Array(raw.split("-"))
		if parts.size() < 5:
			return {"ok": false}
		var port_str: String = str(parts.pop_back())
		if not port_str.is_valid_int():
			return {"ok": false}
		var ip := ".".join(parts)
		if ip.is_empty():
			return {"ok": false}
		return {"ok": true, "ip": ip, "port": int(port_str)}

	# Current format: 8 uppercase hex chars = full IPv4. Port = default_port.
	if code.length() == 8 and _is_hex(code):
		var ip_u32 := code.hex_to_int() & 0xFFFFFFFF
		var ip := _u32_to_ipv4(ip_u32)
		if ip.is_empty():
			return {"ok": false}
		return {"ok": true, "ip": ip, "port": _config.default_port}

	# Back-compat: 10-char base36 = full IPv4 (32 bits) + port (16 bits).
	if code.length() == 10 and _is_base36(code):
		var packed := _from_base36(code)
		if packed < 0:
			return {"ok": false}
		var ip_u32: int = (packed >> 16) & 0xFFFFFFFF
		var port: int = packed & 0xFFFF
		if port <= 0 or port > 65535:
			return {"ok": false}
		var ip := _u32_to_ipv4(ip_u32)
		if ip.is_empty():
			return {"ok": false}
		return {"ok": true, "ip": ip, "port": port}

	# Back-compat: 6-char base36 = /24 prefix + last octet + port.
	if code.length() == 6 and _is_base36(code):
		var packed6 := _from_base36(code)
		if packed6 < 0:
			return {"ok": false}
		var last_octet: int = (packed6 >> 16) & 0xFF
		var port6: int = packed6 & 0xFFFF
		if last_octet <= 0 or last_octet > 255:
			return {"ok": false}
		if port6 <= 0 or port6 > 65535:
			return {"ok": false}
		var local_ip := _resolve_host_ip()
		var prefix := _get_ipv4_prefix_24(local_ip)
		if prefix.is_empty():
			return {"ok": false}
		var ip6 := "%s.%d" % [prefix, last_octet]
		return {"ok": true, "ip": ip6, "port": port6}

	return {"ok": false}


func _get_ipv4_last_octet(ip: String) -> int:
	var parts := ip.strip_edges().split(".")
	if parts.size() != 4:
		return -1
	var last := String(parts[3])
	if not last.is_valid_int():
		return -1
	var v := int(last)
	if v < 0 or v > 255:
		return -1
	return v


func _get_ipv4_prefix_24(ip: String) -> String:
	var parts := ip.strip_edges().split(".")
	if parts.size() != 4:
		return ""
	return "%s.%s.%s" % [String(parts[0]), String(parts[1]), String(parts[2])]


func _ipv4_to_u32(ip: String) -> int:
	var parts := ip.strip_edges().split(".")
	if parts.size() != 4:
		return -1
	var a_str := String(parts[0])
	var b_str := String(parts[1])
	var c_str := String(parts[2])
	var d_str := String(parts[3])
	if not (a_str.is_valid_int() and b_str.is_valid_int() and c_str.is_valid_int() and d_str.is_valid_int()):
		return -1
	var a := int(a_str)
	var b := int(b_str)
	var c := int(c_str)
	var d := int(d_str)
	if a < 0 or a > 255: return -1
	if b < 0 or b > 255: return -1
	if c < 0 or c > 255: return -1
	if d < 0 or d > 255: return -1
	return ((a << 24) | (b << 16) | (c << 8) | d) & 0xFFFFFFFF


func _u32_to_ipv4(ip_u32: int) -> String:
	var v := int(ip_u32) & 0xFFFFFFFF
	var a := (v >> 24) & 0xFF
	var b := (v >> 16) & 0xFF
	var c := (v >> 8) & 0xFF
	var d := v & 0xFF
	return "%d.%d.%d.%d" % [a, b, c, d]


func _is_hex(code: String) -> bool:
	var valid := "0123456789ABCDEF"
	for i in range(code.length()):
		if valid.find(code[i]) < 0:
			return false
	return true


func _to_base36_padded(value: int, width: int) -> String:
	var out := _to_base36(value)
	while out.length() < width:
		out = "0" + out
	if out.length() > width:
		out = out.substr(out.length() - width)
	return out


func _to_base36(value: int) -> String:
	var chars := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var v := int(value)
	if v <= 0:
		return "0"
	var s := ""
	while v > 0:
		var r := v % 36
		s = chars[r] + s
		v = v / 36
	return s


func _from_base36(code: String) -> int:
	var chars := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var v := 0
	for i in range(code.length()):
		var c := code[i]
		var idx := chars.find(c)
		if idx < 0:
			return -1
		v = v * 36 + idx
	return v


func _is_base36(code: String) -> bool:
	var chars := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	for i in range(code.length()):
		if chars.find(code[i]) < 0:
			return false
	return true


func _resolve_host_ip() -> String:
	var addresses: PackedStringArray = IP.get_local_addresses()
	for addr: String in addresses:
		if "." not in addr:
			continue
		if addr.begins_with("127."):
			continue
		if addr.begins_with("169.254."):
			continue
		return addr
	return "127.0.0.1"
