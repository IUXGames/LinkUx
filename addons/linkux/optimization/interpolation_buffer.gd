class_name InterpolationBuffer
extends RefCounted
## Ring buffer of timestamped snapshots for client-side interpolation.
## Samples between two bracketing snapshots to produce smooth rendering.

var _buffer: Array[Dictionary] = []
var _max_size: int = 30
var _interpolation_delay_ms: float = 100.0


func _init(max_size: int = 30, delay_ms: float = 100.0) -> void:
	_max_size = max_size
	_interpolation_delay_ms = delay_ms


func push_snapshot(tick: int, timestamp_ms: float, state: Dictionary) -> void:
	_buffer.append({
		"tick": tick,
		"timestamp": timestamp_ms,
		"state": state,
	})

	if _buffer.size() > _max_size:
		_buffer.pop_front()


func sample(render_time_ms: float) -> Dictionary:
	## Returns an interpolated state for the given render time.
	if _buffer.is_empty():
		return {}

	if _buffer.size() == 1:
		return _buffer[0]["state"]

	var target_time := render_time_ms - _interpolation_delay_ms

	# Find bracketing snapshots
	var before: Dictionary = _buffer[0]
	var after: Dictionary = _buffer[0]

	for i: int in range(_buffer.size() - 1):
		if _buffer[i]["timestamp"] <= target_time and _buffer[i + 1]["timestamp"] >= target_time:
			before = _buffer[i]
			after = _buffer[i + 1]
			break

	# If target is before all snapshots, use oldest
	if target_time <= _buffer[0]["timestamp"]:
		return _buffer[0]["state"]

	# If target is after all snapshots, use newest
	if target_time >= _buffer[_buffer.size() - 1]["timestamp"]:
		return _buffer[_buffer.size() - 1]["state"]

	# Interpolate
	var time_range = after["timestamp"] - before["timestamp"]
	if time_range <= 0.0:
		return after["state"]

	var t = (target_time - before["timestamp"]) / time_range
	t = clampf(t, 0.0, 1.0)

	return _interpolate_states(before["state"], after["state"], t)


func get_buffer_size() -> int:
	return _buffer.size()


func clear() -> void:
	_buffer.clear()


func _interpolate_states(state_a: Dictionary, state_b: Dictionary, t: float) -> Dictionary:
	var result: Dictionary = {}

	for key: String in state_b:
		if not state_a.has(key):
			result[key] = state_b[key]
			continue

		var a: Variant = state_a[key]
		var b: Variant = state_b[key]
		result[key] = _interpolate_value(a, b, t)

	return result


func _interpolate_value(a: Variant, b: Variant, t: float) -> Variant:
	if typeof(a) != typeof(b):
		return b

	if a is float:
		return lerpf(a, b, t)
	if a is int:
		return int(lerpf(float(a), float(b), t))
	if a is Vector2:
		return a.lerp(b, t)
	if a is Vector3:
		return a.lerp(b, t)
	if a is Quaternion:
		return a.slerp(b, t)
	if a is Color:
		return a.lerp(b, t)
	if a is Basis:
		return a.slerp(b, t)
	if a is Transform2D:
		return a.interpolate_with(b, t)
	if a is Transform3D:
		return a.interpolate_with(b, t)

	# Non-interpolable: snap to newer value at midpoint
	return a if t < 0.5 else b
