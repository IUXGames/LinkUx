class_name InternalStateMachine
extends RefCounted
## Manages LinkUx internal state transitions with validation.

signal state_changed(old_state: int, new_state: int)

var _state: int = NetworkEnums.InternalState.INIT
var _logger: DebugLogger

## Valid transitions map: state -> Array of allowed target states.
var _transitions: Dictionary = {
	NetworkEnums.InternalState.INIT: [
		NetworkEnums.InternalState.READY,
		NetworkEnums.InternalState.ERROR,
	],
	NetworkEnums.InternalState.READY: [
		NetworkEnums.InternalState.CONNECTING,
		NetworkEnums.InternalState.ERROR,
	],
	NetworkEnums.InternalState.CONNECTING: [
		NetworkEnums.InternalState.IN_SESSION,
		NetworkEnums.InternalState.READY,
		NetworkEnums.InternalState.ERROR,
	],
	NetworkEnums.InternalState.IN_SESSION: [
		NetworkEnums.InternalState.RUNNING,
		NetworkEnums.InternalState.DISCONNECTING,
		NetworkEnums.InternalState.ERROR,
	],
	NetworkEnums.InternalState.RUNNING: [
		NetworkEnums.InternalState.DISCONNECTING,
		NetworkEnums.InternalState.ERROR,
	],
	NetworkEnums.InternalState.DISCONNECTING: [
		NetworkEnums.InternalState.READY,
		NetworkEnums.InternalState.ERROR,
	],
	NetworkEnums.InternalState.ERROR: [
		NetworkEnums.InternalState.INIT,
		NetworkEnums.InternalState.READY,
	],
}


func _init(logger: DebugLogger = null) -> void:
	_logger = logger


func get_state() -> int:
	return _state


func get_state_name() -> String:
	match _state:
		NetworkEnums.InternalState.INIT: return "INIT"
		NetworkEnums.InternalState.READY: return "READY"
		NetworkEnums.InternalState.CONNECTING: return "CONNECTING"
		NetworkEnums.InternalState.IN_SESSION: return "IN_SESSION"
		NetworkEnums.InternalState.RUNNING: return "RUNNING"
		NetworkEnums.InternalState.DISCONNECTING: return "DISCONNECTING"
		NetworkEnums.InternalState.ERROR: return "ERROR"
		_: return "UNKNOWN"


func can_transition_to(new_state: int) -> bool:
	if not _transitions.has(_state):
		return false
	var allowed: Array = _transitions[_state]
	return new_state in allowed


func transition_to(new_state: int) -> bool:
	if not can_transition_to(new_state):
		if _logger:
			_logger.error(
				"Invalid state transition: %s -> %s" % [get_state_name(), _state_name(new_state)],
				"StateMachine"
			)
		return false

	var old_state := _state
	_state = new_state

	if _logger:
		_logger.info(
			"State: %s -> %s" % [_state_name(old_state), _state_name(new_state)],
			"StateMachine"
		)

	state_changed.emit(old_state, new_state)
	return true


func force_state(new_state: int) -> void:
	var old_state := _state
	_state = new_state
	state_changed.emit(old_state, new_state)


func is_state(check_state: int) -> bool:
	return _state == check_state


func _state_name(s: int) -> String:
	match s:
		NetworkEnums.InternalState.INIT: return "INIT"
		NetworkEnums.InternalState.READY: return "READY"
		NetworkEnums.InternalState.CONNECTING: return "CONNECTING"
		NetworkEnums.InternalState.IN_SESSION: return "IN_SESSION"
		NetworkEnums.InternalState.RUNNING: return "RUNNING"
		NetworkEnums.InternalState.DISCONNECTING: return "DISCONNECTING"
		NetworkEnums.InternalState.ERROR: return "ERROR"
		_: return "UNKNOWN(%d)" % s
