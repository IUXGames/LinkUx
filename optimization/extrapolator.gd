class_name Extrapolator
extends RefCounted
## Dead-reckoning prediction when the interpolation buffer runs dry.
## Estimates future state based on last known velocity, capped by a time limit.

var _last_state: Dictionary = {}
var _velocity: Dictionary = {}
var _last_timestamp: float = 0.0
var _extrapolation_limit_ms: float = 250.0


func _init(limit_ms: float = 250.0) -> void:
	_extrapolation_limit_ms = limit_ms


func update(timestamp_ms: float, state: Dictionary) -> void:
	## Feed a new state to compute velocity.
	if _last_timestamp > 0.0 and timestamp_ms > _last_timestamp:
		var dt := (timestamp_ms - _last_timestamp) / 1000.0
		if dt > 0.0:
			_velocity.clear()
			for key: String in state:
				if _last_state.has(key):
					var vel: Variant = _compute_velocity(_last_state[key], state[key], dt)
					if vel != null:
						_velocity[key] = vel

	_last_state = state.duplicate()
	_last_timestamp = timestamp_ms


func extrapolate(current_time_ms: float) -> Dictionary:
	## Predict state at current_time_ms based on last known state + velocity.
	if _last_timestamp <= 0.0:
		return _last_state

	var elapsed_ms := current_time_ms - _last_timestamp
	if elapsed_ms <= 0.0:
		return _last_state
	if elapsed_ms > _extrapolation_limit_ms:
		elapsed_ms = _extrapolation_limit_ms

	var dt := elapsed_ms / 1000.0
	var predicted: Dictionary = _last_state.duplicate()

	for key: String in _velocity:
		if predicted.has(key):
			predicted[key] = _apply_velocity(predicted[key], _velocity[key], dt)

	return predicted


func has_data() -> bool:
	return _last_timestamp > 0.0


func clear() -> void:
	_last_state.clear()
	_velocity.clear()
	_last_timestamp = 0.0


func _compute_velocity(old_val: Variant, new_val: Variant, dt: float) -> Variant:
	if old_val is float and new_val is float:
		return (new_val - old_val) / dt
	if old_val is Vector2 and new_val is Vector2:
		return (new_val - old_val) / dt
	if old_val is Vector3 and new_val is Vector3:
		return (new_val - old_val) / dt
	return null


func _apply_velocity(value: Variant, velocity: Variant, dt: float) -> Variant:
	if value is float and velocity is float:
		return value + velocity * dt
	if value is Vector2 and velocity is Vector2:
		return value + velocity * dt
	if value is Vector3 and velocity is Vector3:
		return value + velocity * dt
	return value
