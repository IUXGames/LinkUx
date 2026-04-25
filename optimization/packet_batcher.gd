class_name PacketBatcher
extends RefCounted
## Accumulates outgoing messages per peer per tick and flushes them as
## single combined packets to reduce UDP overhead.

var _queues: Dictionary = {}  # peer_id -> Array[{data, channel, reliable}]
var _enabled: bool = true


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func queue(peer_id: int, data: PackedByteArray, channel: int, reliable: bool) -> void:
	if not _enabled:
		return
	if not _queues.has(peer_id):
		_queues[peer_id] = []
	_queues[peer_id].append({
		"data": data,
		"channel": channel,
		"reliable": reliable,
	})


func flush(transport: TransportLayer) -> void:
	for peer_id: int in _queues:
		var messages: Array = _queues[peer_id]
		if messages.is_empty():
			continue

		# Group by channel + reliability
		var groups: Dictionary = {}
		for msg: Dictionary in messages:
			var key := "%d_%s" % [msg["channel"], msg["reliable"]]
			if not groups.has(key):
				groups[key] = {
					"channel": msg["channel"],
					"reliable": msg["reliable"],
					"packets": [],
				}
			groups[key]["packets"].append(msg["data"])

		for key: String in groups:
			var group: Dictionary = groups[key]
			var batched := _batch_packets(group["packets"])
			transport.send(peer_id, batched, group["channel"], group["reliable"])

	_queues.clear()


func _batch_packets(packets: Array) -> PackedByteArray:
	if packets.size() == 1:
		return packets[0]

	# Format: [2B count][for each: 2B size + data]
	var total_size := 2
	for pkt: PackedByteArray in packets:
		total_size += 2 + pkt.size()

	var buffer := PackedByteArray()
	buffer.resize(total_size)
	var offset := 0

	# Packet count
	buffer[offset] = (packets.size() >> 8) & 0xFF
	buffer[offset + 1] = packets.size() & 0xFF
	offset += 2

	for pkt: PackedByteArray in packets:
		# Packet size
		buffer[offset] = (pkt.size() >> 8) & 0xFF
		buffer[offset + 1] = pkt.size() & 0xFF
		offset += 2
		# Packet data
		for i: int in pkt.size():
			buffer[offset + i] = pkt[i]
		offset += pkt.size()

	return buffer


static func unbatch_packets(data: PackedByteArray) -> Array[PackedByteArray]:
	var result: Array[PackedByteArray] = []

	# Check if this is a batched packet (has valid count header and size > HEADER_SIZE + 2)
	if data.size() < MessageSerializer.HEADER_SIZE + 4:
		# Not batched, return as single packet
		result.append(data)
		return result

	# Peek at the first byte to check if it's a message type header
	# If first byte matches a known message type, it's a single message
	if data[0] > 0 and data.size() >= MessageSerializer.HEADER_SIZE:
		result.append(data)
		return result

	# Batched format: [2B count][2B size + data]...
	var count := (data[0] << 8) | data[1]
	if count <= 0 or count > 1000:
		result.append(data)
		return result

	var offset := 2
	for _i: int in count:
		if offset + 2 > data.size():
			break
		var pkt_size := (data[offset] << 8) | data[offset + 1]
		offset += 2
		if offset + pkt_size > data.size():
			break
		result.append(data.slice(offset, offset + pkt_size))
		offset += pkt_size

	return result


func get_pending_count() -> int:
	var total := 0
	for peer_id: int in _queues:
		total += _queues[peer_id].size()
	return total
