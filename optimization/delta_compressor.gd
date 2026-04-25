class_name DeltaCompressor
extends RefCounted
## Computes and applies state deltas using bitmask encoding.
## Only changed properties are transmitted, reducing bandwidth significantly.


static func compute_delta(old_state: Dictionary, new_state: Dictionary) -> Dictionary:
	## Returns a delta dictionary containing only changed key-value pairs.
	## Empty if nothing changed.
	var delta: Dictionary = {}

	for key: String in new_state:
		if not old_state.has(key) or not _values_equal(old_state[key], new_state[key]):
			delta[key] = new_state[key]

	return delta


static func apply_delta(base_state: Dictionary, delta: Dictionary) -> Dictionary:
	## Merges delta onto base_state and returns the resulting state.
	var result := base_state.duplicate()
	for key: String in delta:
		result[key] = delta[key]
	return result


static func serialize_delta(delta: Dictionary, property_keys: Array[String]) -> PackedByteArray:
	## Serializes a delta using a bitmask for which properties changed,
	## followed by the changed values.
	if delta.is_empty():
		return PackedByteArray()

	# Build bitmask
	var bitmask := 0
	for i: int in property_keys.size():
		if delta.has(property_keys[i]):
			bitmask |= (1 << i)

	# Serialize: [bitmask bytes][changed values via var_to_bytes]
	var changed_values: Dictionary = {}
	for key: String in delta:
		changed_values[key] = delta[key]

	var value_bytes := var_to_bytes(changed_values)
	var bitmask_size := _bitmask_byte_count(property_keys.size())

	var buffer := PackedByteArray()
	buffer.resize(bitmask_size + value_bytes.size())

	# Write bitmask
	for i: int in bitmask_size:
		buffer[i] = (bitmask >> (i * 8)) & 0xFF

	# Write values
	for i: int in value_bytes.size():
		buffer[bitmask_size + i] = value_bytes[i]

	return buffer


static func deserialize_delta(data: PackedByteArray, property_keys: Array[String]) -> Dictionary:
	## Deserializes a bitmask-encoded delta.
	if data.is_empty():
		return {}

	var bitmask_size := _bitmask_byte_count(property_keys.size())
	if data.size() < bitmask_size:
		return {}

	# Read bitmask
	var bitmask := 0
	for i: int in bitmask_size:
		bitmask |= data[i] << (i * 8)

	# Read values
	var value_slice := data.slice(bitmask_size)
	var changed_values: Variant = bytes_to_var(value_slice)

	if changed_values is Dictionary:
		return changed_values
	return {}


static func _values_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	# For floating point, use approximate comparison
	if a is float:
		return absf(a - b) < 0.0001
	if a is Vector2:
		return a.distance_to(b) < 0.001
	if a is Vector3:
		return a.distance_to(b) < 0.001
	return a == b


static func _bitmask_byte_count(property_count: int) -> int:
	return ceili(property_count / 8.0)
