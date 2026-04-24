class_name RpcRelay
extends Node
## Abstract RPC system. Serializes method calls and routes through the transport layer.
## Supports reliable and unreliable channels.

var _transport: TransportLayer
var _events: NetworkEvents
var _logger: DebugLogger
var _batcher: PacketBatcher
var _config: NetworkConfig
var _sequence: int = 0

## Registered RPC handlers: method_name -> Callable
var _handlers: Dictionary = {}

## Tick-level rate tracking
var _rpcs_this_tick: int = 0


func setup(transport: TransportLayer, events: NetworkEvents, logger: DebugLogger, config: NetworkConfig) -> void:
	if _events and _events.data_received.is_connected(_on_data_received):
		_events.data_received.disconnect(_on_data_received)

	_transport = transport
	_events = events
	_logger = logger
	_config = config
	_batcher = PacketBatcher.new()
	_batcher.set_enabled(config.packet_batch_enabled if config else true)

	# Listen for incoming data to intercept RPC messages
	if _events and not _events.data_received.is_connected(_on_data_received):
		_events.data_received.connect(_on_data_received)


func register_handler(method_name: String, callable: Callable) -> void:
	_handlers[method_name] = callable


func unregister_handler(method_name: String) -> void:
	_handlers.erase(method_name)


func send_rpc(target_peer: int, method_name: String, args: Array = [], reliable: bool = true) -> void:
	if _config and _rpcs_this_tick >= _config.max_rpc_per_tick:
		_logger.warn("RPC rate limit exceeded for this tick", "RpcRelay")
		return

	var payload := {
		"method": method_name,
		"args": args,
	}

	var msg_type := NetworkEnums.MessageType.RPC_RELIABLE if reliable else NetworkEnums.MessageType.RPC_UNRELIABLE
	_sequence = (_sequence + 1) % 256

	var tick := 0
	var tick_manager: Node = get_parent().get_node_or_null("TickManager")
	if tick_manager and tick_manager.has_method("get_current_tick"):
		tick = tick_manager.get_current_tick()

	var data := MessageSerializer.serialize_message(msg_type, tick, _sequence, payload)

	var channel := NetworkEnums.ChannelType.RPC
	if _batcher and _config and _config.packet_batch_enabled:
		_batcher.queue(target_peer, data, channel, reliable)
	else:
		_transport.send(target_peer, data, channel, reliable)

	_rpcs_this_tick += 1
	_logger.trace("RPC sent: %s -> peer %d" % [method_name, target_peer], "RpcRelay")


func flush() -> void:
	if _batcher:
		_batcher.flush(_transport)
	_rpcs_this_tick = 0


func _on_data_received(from_peer: int, _channel: int, data: PackedByteArray) -> void:
	if data.size() < MessageSerializer.HEADER_SIZE:
		return

	var header := MessageSerializer.deserialize_header(data)
	var msg_type: int = header.get("type", -1)

	if msg_type != NetworkEnums.MessageType.RPC_RELIABLE and msg_type != NetworkEnums.MessageType.RPC_UNRELIABLE:
		return

	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return

	var method_name: String = payload.get("method", "")
	var args: Array = payload.get("args", [])

	if method_name == "":
		_logger.warn("Received RPC with empty method name from peer %d" % from_peer, "RpcRelay")
		return

	if _handlers.has(method_name):
		var callable: Callable = _handlers[method_name]
		if not callable.is_valid():
			_handlers.erase(method_name)
			_logger.warn("Removed stale RPC handler '%s' (target no longer valid)" % method_name, "RpcRelay")
			return
		# Prepend from_peer so handler knows who called
		var full_args: Array = [from_peer]
		full_args.append_array(args)
		callable.callv(full_args)
		_logger.trace("RPC received: %s from peer %d" % [method_name, from_peer], "RpcRelay")
	else:
		_logger.debug("No handler for RPC '%s' from peer %d" % [method_name, from_peer], "RpcRelay")
