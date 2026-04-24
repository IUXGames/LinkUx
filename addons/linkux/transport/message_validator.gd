class_name MessageValidator
extends RefCounted
## Validates incoming and outgoing packets for size and basic structure.

var max_packet_size: int = 4096


func validate_outgoing(data: PackedByteArray) -> bool:
	if data.is_empty():
		return false
	if data.size() > max_packet_size:
		return false
	# Must have at least the header
	if data.size() < MessageSerializer.HEADER_SIZE:
		return false
	return true


func validate_incoming(data: PackedByteArray) -> bool:
	if data.is_empty():
		return false
	if data.size() < MessageSerializer.HEADER_SIZE:
		return false
	return true
