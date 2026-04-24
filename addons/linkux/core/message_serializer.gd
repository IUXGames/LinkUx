class_name MessageSerializer
extends RefCounted
## Unified serializer for all LinkUx network messages.
## Every message has a header: [1B type][4B tick][1B sequence][payload].

const HEADER_SIZE := 6


static func serialize_message(type: int, tick: int, sequence: int, payload: Dictionary) -> PackedByteArray:
	var payload_bytes := var_to_bytes(payload)
	var buffer := PackedByteArray()
	buffer.resize(HEADER_SIZE + payload_bytes.size())

	buffer[0] = type & 0xFF
	buffer[1] = (tick >> 24) & 0xFF
	buffer[2] = (tick >> 16) & 0xFF
	buffer[3] = (tick >> 8) & 0xFF
	buffer[4] = tick & 0xFF
	buffer[5] = sequence & 0xFF

	for i: int in payload_bytes.size():
		buffer[HEADER_SIZE + i] = payload_bytes[i]

	return buffer


static func deserialize_header(data: PackedByteArray) -> Dictionary:
	if data.size() < HEADER_SIZE:
		return {}

	var type := data[0]
	var tick := (data[1] << 24) | (data[2] << 16) | (data[3] << 8) | data[4]
	var sequence := data[5]

	return {
		"type": type,
		"tick": tick,
		"sequence": sequence,
	}


static func deserialize_payload(data: PackedByteArray) -> Variant:
	if data.size() <= HEADER_SIZE:
		return {}
	var payload_slice := data.slice(HEADER_SIZE)
	return bytes_to_var(payload_slice)


static func deserialize_message(data: PackedByteArray) -> Dictionary:
	var header := deserialize_header(data)
	if header.is_empty():
		return {}
	var payload: Variant = deserialize_payload(data)
	header["payload"] = payload
	return header


static func serialize_raw(type: int, tick: int, sequence: int, raw_payload: PackedByteArray) -> PackedByteArray:
	var buffer := PackedByteArray()
	buffer.resize(HEADER_SIZE + raw_payload.size())

	buffer[0] = type & 0xFF
	buffer[1] = (tick >> 24) & 0xFF
	buffer[2] = (tick >> 16) & 0xFF
	buffer[3] = (tick >> 8) & 0xFF
	buffer[4] = tick & 0xFF
	buffer[5] = sequence & 0xFF

	for i: int in raw_payload.size():
		buffer[HEADER_SIZE + i] = raw_payload[i]

	return buffer
