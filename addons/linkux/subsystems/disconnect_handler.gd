class_name DisconnectHandler
extends Node
## Manages heartbeat monitoring, timeout detection, and graceful disconnection.

var _transport: TransportLayer
var _events: NetworkEvents
var _logger: DebugLogger
var _net_config: NetworkConfig
var _adv_config: AdvancedConfig

## Last heartbeat timestamp per peer (msec).
var _last_heartbeat: Dictionary = {}

## Last time we sent a heartbeat.
var _last_sent_heartbeat: int = 0

## RTT tracking per peer (msec).
var _peer_rtt: Dictionary = {}

## Heartbeat send timestamps for RTT calculation.
var _heartbeat_sent_at: Dictionary = {}

var _sequence: int = 0
var _timed_out_peers: Dictionary = {}  # peer_id -> true (prevents duplicate timeout emits)


func setup(transport: TransportLayer, events: NetworkEvents, logger: DebugLogger, net_config: NetworkConfig, adv_config: AdvancedConfig) -> void:
	if _events:
		if _events.data_received.is_connected(_on_data_received):
			_events.data_received.disconnect(_on_data_received)
		if _events.peer_connected.is_connected(_on_peer_connected):
			_events.peer_connected.disconnect(_on_peer_connected)
		if _events.peer_disconnected.is_connected(_on_peer_disconnected):
			_events.peer_disconnected.disconnect(_on_peer_disconnected)

	_transport = transport
	_events = events
	_logger = logger
	_net_config = net_config
	_adv_config = adv_config

	if _events:
		if not _events.data_received.is_connected(_on_data_received):
			_events.data_received.connect(_on_data_received)
		if not _events.peer_connected.is_connected(_on_peer_connected):
			_events.peer_connected.connect(_on_peer_connected)
		if not _events.peer_disconnected.is_connected(_on_peer_disconnected):
			_events.peer_disconnected.connect(_on_peer_disconnected)


func reset() -> void:
	_last_heartbeat.clear()
	_peer_rtt.clear()
	_heartbeat_sent_at.clear()
	_timed_out_peers.clear()
	_last_sent_heartbeat = 0
	_sequence = 0


func process_tick(_tick: int, _delta: float) -> void:
	var now := Time.get_ticks_msec()

	# Send heartbeat periodically
	var interval := _net_config.heartbeat_interval_ms if _net_config else 5000.0
	if now - _last_sent_heartbeat >= int(interval):
		_send_heartbeat()
		_last_sent_heartbeat = now

	_check_timeouts(now)


func get_stats() -> Dictionary:
	var stats: Dictionary = {}
	for peer_id: int in _peer_rtt:
		stats[peer_id] = {
			"rtt_ms": _peer_rtt[peer_id],
			"last_heartbeat_ms": _last_heartbeat.get(peer_id, 0),
		}
	return stats


func get_peer_rtt(peer_id: int) -> float:
	return _peer_rtt.get(peer_id, -1.0)


# ── Internal ─────────────────────────────────────────────────────────────────

func _send_heartbeat() -> void:
	var now := Time.get_ticks_msec()
	_sequence = (_sequence + 1) % 256
	var payload := {"timestamp": now}
	var data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.HEARTBEAT, 0, _sequence, payload
	)
	_transport.broadcast(data, NetworkEnums.ChannelType.CONTROL, false)
	_heartbeat_sent_at[_sequence] = now


func _check_timeouts(now: int) -> void:
	var timeout := _net_config.disconnect_timeout_ms if _net_config else 15000.0
	var timed_out: Array[int] = []

	for peer_id: int in _last_heartbeat:
		if now - _last_heartbeat[peer_id] > int(timeout):
			timed_out.append(peer_id)

	var linkux: Node = get_parent()
	var local_is_host: bool = linkux and linkux.has_method("is_host") and linkux.is_host()
	var local_peer_id: int = linkux.get_local_peer_id() if linkux and linkux.has_method("get_local_peer_id") else -1

	for peer_id: int in timed_out:
		if _timed_out_peers.has(peer_id):
			continue
		# In ENet server-client topology, non-host peers should only timeout-check the host (peer 1).
		# Other peers are observed authoritatively by the host and propagated via backend peer events.
		if not local_is_host and peer_id != 1:
			_last_heartbeat.erase(peer_id)
			_peer_rtt.erase(peer_id)
			continue
		# Ignore invalid/self entries that can appear during reconnect churn.
		if peer_id <= 0 or peer_id == local_peer_id:
			_last_heartbeat.erase(peer_id)
			_peer_rtt.erase(peer_id)
			continue
		_logger.warn("Peer %d timed out (no heartbeat for %.1fs)" % [peer_id, timeout / 1000.0], "DisconnectHandler")
		_last_heartbeat.erase(peer_id)
		_peer_rtt.erase(peer_id)
		_timed_out_peers[peer_id] = true
		var reason: int = NetworkEnums.DisconnectReason.TIMEOUT
		if peer_id == 1 and not local_is_host:
			reason = NetworkEnums.DisconnectReason.HOST_CLOSED
		_events.player_left.emit(peer_id, reason)
		_events.peer_disconnected.emit(peer_id, reason)


func _on_peer_connected(peer_id: int) -> void:
	_timed_out_peers.erase(peer_id)
	_last_heartbeat[peer_id] = Time.get_ticks_msec()
	_peer_rtt[peer_id] = 0.0


func _on_peer_disconnected(peer_id: int, _reason: int) -> void:
	_timed_out_peers.erase(peer_id)
	_last_heartbeat.erase(peer_id)
	_peer_rtt.erase(peer_id)


func _on_data_received(from_peer: int, _channel: int, data: PackedByteArray) -> void:
	if data.size() < MessageSerializer.HEADER_SIZE:
		return

	var header := MessageSerializer.deserialize_header(data)
	var msg_type: int = header.get("type", -1)

	match msg_type:
		NetworkEnums.MessageType.HEARTBEAT:
			_handle_heartbeat(from_peer, data)
		NetworkEnums.MessageType.HEARTBEAT_ACK:
			_handle_heartbeat_ack(from_peer, data)


func _handle_heartbeat(from_peer: int, data: PackedByteArray) -> void:
	_last_heartbeat[from_peer] = Time.get_ticks_msec()

	# Send ACK back
	var payload: Variant = MessageSerializer.deserialize_payload(data)
	_sequence = (_sequence + 1) % 256
	var ack_data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.HEARTBEAT_ACK, 0, _sequence,
		payload if payload is Dictionary else {}
	)
	_transport.send(from_peer, ack_data, NetworkEnums.ChannelType.CONTROL, false)


func _handle_heartbeat_ack(from_peer: int, data: PackedByteArray) -> void:
	var now := Time.get_ticks_msec()
	_last_heartbeat[from_peer] = now

	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if payload is Dictionary:
		var sent_at: int = payload.get("timestamp", 0)
		if sent_at > 0:
			_peer_rtt[from_peer] = float(now - sent_at)
