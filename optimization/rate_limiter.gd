class_name RateLimiter
extends RefCounted
## Enforces limits on packet size, RPC frequency, and bandwidth.

var max_packet_size: int = 4096
var max_rpc_per_tick: int = 10
var max_state_updates_per_entity_per_tick: int = 1
var max_bandwidth_per_second: int = 1024000  # bytes

var _rpc_count_this_tick: int = 0
var _entity_update_counts: Dictionary = {}  # entity_path -> count this tick
var _bytes_sent_this_second: int = 0
var _second_start_time: int = 0


func configure(config: NetworkConfig, advanced: AdvancedConfig) -> void:
	if config:
		max_packet_size = config.max_packet_size
		max_rpc_per_tick = config.max_rpc_per_tick
	if advanced:
		max_state_updates_per_entity_per_tick = advanced.max_state_updates_per_entity_per_tick
		max_bandwidth_per_second = advanced.max_bandwidth_per_second


func can_send_rpc() -> bool:
	return _rpc_count_this_tick < max_rpc_per_tick


func record_rpc() -> void:
	_rpc_count_this_tick += 1


func can_update_entity(entity_path: NodePath) -> bool:
	var count: int = _entity_update_counts.get(entity_path, 0)
	return count < max_state_updates_per_entity_per_tick


func record_entity_update(entity_path: NodePath) -> void:
	_entity_update_counts[entity_path] = _entity_update_counts.get(entity_path, 0) + 1


func can_send_bytes(size: int) -> bool:
	_refresh_second()
	return _bytes_sent_this_second + size <= max_bandwidth_per_second


func record_bytes_sent(size: int) -> void:
	_refresh_second()
	_bytes_sent_this_second += size


func validate_packet_size(data: PackedByteArray) -> bool:
	return data.size() <= max_packet_size


func reset_tick() -> void:
	_rpc_count_this_tick = 0
	_entity_update_counts.clear()


func _refresh_second() -> void:
	var now := Time.get_ticks_msec()
	if now - _second_start_time >= 1000:
		_bytes_sent_this_second = 0
		_second_start_time = now
