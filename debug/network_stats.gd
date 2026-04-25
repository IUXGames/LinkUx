class_name NetworkStats
extends RefCounted
## Real-time network metrics: RTT, packet loss, bandwidth, tick jitter.

var _rtt_samples: Dictionary = {}  # peer_id -> Array[float]
var _bytes_sent: int = 0
var _bytes_received: int = 0
var _packets_sent: int = 0
var _packets_received: int = 0
var _packets_lost: int = 0
var _last_tick_time: int = 0
var _tick_jitter_samples: Array[float] = []
var _sample_start_time: int = 0

const MAX_RTT_SAMPLES := 20
const MAX_JITTER_SAMPLES := 50


func record_rtt(peer_id: int, rtt_ms: float) -> void:
	if not _rtt_samples.has(peer_id):
		_rtt_samples[peer_id] = []
	_rtt_samples[peer_id].append(rtt_ms)
	if _rtt_samples[peer_id].size() > MAX_RTT_SAMPLES:
		_rtt_samples[peer_id].pop_front()


func record_bytes_sent(count: int) -> void:
	_bytes_sent += count
	_packets_sent += 1


func record_bytes_received(count: int) -> void:
	_bytes_received += count
	_packets_received += 1


func record_packet_loss() -> void:
	_packets_lost += 1


func record_tick() -> void:
	var now := Time.get_ticks_msec()
	if _last_tick_time > 0:
		var delta := float(now - _last_tick_time)
		_tick_jitter_samples.append(delta)
		if _tick_jitter_samples.size() > MAX_JITTER_SAMPLES:
			_tick_jitter_samples.pop_front()
	_last_tick_time = now


func get_average_rtt(peer_id: int) -> float:
	if not _rtt_samples.has(peer_id) or _rtt_samples[peer_id].is_empty():
		return -1.0
	var samples: Array = _rtt_samples[peer_id]
	var total := 0.0
	for s: float in samples:
		total += s
	return total / samples.size()


func get_packet_loss_rate() -> float:
	var total := _packets_sent + _packets_lost
	if total == 0:
		return 0.0
	return float(_packets_lost) / float(total)


func get_bandwidth_sent() -> int:
	return _bytes_sent


func get_bandwidth_received() -> int:
	return _bytes_received


func get_tick_jitter() -> float:
	if _tick_jitter_samples.size() < 2:
		return 0.0
	var avg := 0.0
	for s: float in _tick_jitter_samples:
		avg += s
	avg /= _tick_jitter_samples.size()

	var variance := 0.0
	for s: float in _tick_jitter_samples:
		variance += (s - avg) * (s - avg)
	variance /= _tick_jitter_samples.size()
	return sqrt(variance)


func get_summary() -> Dictionary:
	var rtt_summary: Dictionary = {}
	for peer_id: int in _rtt_samples:
		rtt_summary[peer_id] = get_average_rtt(peer_id)

	return {
		"rtt_per_peer": rtt_summary,
		"packet_loss_rate": get_packet_loss_rate(),
		"bytes_sent": _bytes_sent,
		"bytes_received": _bytes_received,
		"packets_sent": _packets_sent,
		"packets_received": _packets_received,
		"tick_jitter_ms": get_tick_jitter(),
	}


func reset() -> void:
	_rtt_samples.clear()
	_bytes_sent = 0
	_bytes_received = 0
	_packets_sent = 0
	_packets_received = 0
	_packets_lost = 0
	_tick_jitter_samples.clear()
	_last_tick_time = 0
