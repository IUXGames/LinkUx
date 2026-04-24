class_name DebugHooks
extends RefCounted
## Provides hooks into key LinkUx systems for diagnostics and debug overlay.

var enabled: bool = false

var _tick_log: Array[Dictionary] = []
var _message_log: Array[Dictionary] = []
var _authority_log: Array[Dictionary] = []
var _connection_log: Array[Dictionary] = []

const MAX_LOG_ENTRIES := 500


func log_tick(tick: int, delta: float, entities_replicated: int) -> void:
	if not enabled:
		return
	_tick_log.append({
		"tick": tick,
		"delta": delta,
		"entities": entities_replicated,
		"time": Time.get_ticks_msec(),
	})
	if _tick_log.size() > MAX_LOG_ENTRIES:
		_tick_log.pop_front()


func log_message(type: int, from_peer: int, to_peer: int, size: int) -> void:
	if not enabled:
		return
	_message_log.append({
		"type": type,
		"from": from_peer,
		"to": to_peer,
		"size": size,
		"time": Time.get_ticks_msec(),
	})
	if _message_log.size() > MAX_LOG_ENTRIES:
		_message_log.pop_front()


func log_authority_change(entity_path: String, old_peer: int, new_peer: int) -> void:
	if not enabled:
		return
	_authority_log.append({
		"entity": entity_path,
		"old_peer": old_peer,
		"new_peer": new_peer,
		"time": Time.get_ticks_msec(),
	})
	if _authority_log.size() > MAX_LOG_ENTRIES:
		_authority_log.pop_front()


func log_connection_event(event: String, peer_id: int, details: String = "") -> void:
	if not enabled:
		return
	_connection_log.append({
		"event": event,
		"peer_id": peer_id,
		"details": details,
		"time": Time.get_ticks_msec(),
	})
	if _connection_log.size() > MAX_LOG_ENTRIES:
		_connection_log.pop_front()


func get_tick_log() -> Array[Dictionary]:
	return _tick_log


func get_message_log() -> Array[Dictionary]:
	return _message_log


func get_authority_log() -> Array[Dictionary]:
	return _authority_log


func get_connection_log() -> Array[Dictionary]:
	return _connection_log


func clear_all() -> void:
	_tick_log.clear()
	_message_log.clear()
	_authority_log.clear()
	_connection_log.clear()
