class_name TransportLayer
extends Node
## Unified transport abstraction. Sits between subsystems and the active backend.
## Handles message routing, validation, and channel management.

var _backend: NetworkBackend
var _channel_manager: ChannelManager
var _message_validator: MessageValidator
var _logger: DebugLogger
var _events: NetworkEvents
var _debug_hooks: DebugHooks


func setup(backend: NetworkBackend, events: NetworkEvents, logger: DebugLogger, debug_hooks: DebugHooks, config: NetworkConfig) -> void:
	if _backend and _backend.backend_data_received.is_connected(_on_backend_data_received):
		_backend.backend_data_received.disconnect(_on_backend_data_received)

	_backend = backend
	_events = events
	_logger = logger
	_debug_hooks = debug_hooks

	_channel_manager = ChannelManager.new()
	_message_validator = MessageValidator.new()
	if config:
		_message_validator.max_packet_size = config.max_packet_size

	# Wire backend incoming data to our handler
	if _backend:
		if _backend.backend_data_received.is_connected(_on_backend_data_received):
			_backend.backend_data_received.disconnect(_on_backend_data_received)
		_backend.backend_data_received.connect(_on_backend_data_received)


func send(peer_id: int, data: PackedByteArray, channel: int, reliable: bool) -> Error:
	if _backend == null:
		return ERR_UNCONFIGURED

	if not _message_validator.validate_outgoing(data):
		_logger.warn("Outgoing packet failed validation (size=%d)" % data.size(), "Transport")
		return ERR_INVALID_DATA

	var mapped_channel := _channel_manager.get_backend_channel(channel)

	if _debug_hooks and _debug_hooks.enabled:
		_debug_hooks.log_message(data[0] if data.size() > 0 else -1, _backend._backend_get_local_peer_id(), peer_id, data.size())

	return _backend._backend_send(peer_id, data, mapped_channel, reliable)


func broadcast(data: PackedByteArray, channel: int, reliable: bool) -> Error:
	return send(0, data, channel, reliable)


func host_should_relay_client_state() -> bool:
	if _backend == null or not _backend.has_method("_backend_get_capabilities"):
		return false
	var caps: Dictionary = _backend._backend_get_capabilities()
	return bool(caps.get("host_relays_client_state", false))


func poll() -> void:
	if _backend:
		_backend._backend_poll()


func _on_backend_data_received(from_peer: int, channel: int, data: PackedByteArray) -> void:
	if not _message_validator.validate_incoming(data):
		_logger.warn("Incoming packet from peer %d failed validation" % from_peer, "Transport")
		return

	var packets: Array[PackedByteArray] = PacketBatcher.unbatch_packets(data)
	for pkt: PackedByteArray in packets:
		if not _message_validator.validate_incoming(pkt):
			_logger.warn("Incoming sub-packet from peer %d failed validation" % from_peer, "Transport")
			continue
		if _debug_hooks and _debug_hooks.enabled:
			_debug_hooks.log_message(pkt[0] if pkt.size() > 0 else -1, from_peer, _backend._backend_get_local_peer_id(), pkt.size())
		_events.data_received.emit(from_peer, channel, pkt)
