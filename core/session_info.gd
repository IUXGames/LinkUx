class_name SessionInfo
extends Resource
## Unified session data structure used across all backends.

@export var session_id: String = ""
@export var session_name: String = ""
@export var host_peer_id: int = 1
@export var max_players: int = 16
@export var current_players: int = 0
@export var is_private: bool = false
@export var room_code: String = ""
@export var metadata: Dictionary = {}

## Backend-specific opaque data (IP:port for LAN, custom handles, etc.)
var backend_data: Dictionary = {}

## List of connected peer IDs.
var connected_peers: Array[int] = []


func _to_string() -> String:
	return "SessionInfo<%s | %s | %d/%d>" % [session_id, session_name, current_players, max_players]


func to_dict() -> Dictionary:
	return {
		"session_id": session_id,
		"session_name": session_name,
		"host_peer_id": host_peer_id,
		"max_players": max_players,
		"current_players": current_players,
		"is_private": is_private,
		"room_code": room_code,
		"metadata": metadata,
		"backend_data": backend_data.duplicate(true),
		"connected_peers": connected_peers,
	}


static func from_dict(data: Dictionary) -> SessionInfo:
	var info := SessionInfo.new()
	info.session_id = data.get("session_id", "")
	info.session_name = data.get("session_name", "")
	info.host_peer_id = data.get("host_peer_id", 1)
	info.max_players = data.get("max_players", 16)
	info.current_players = data.get("current_players", 0)
	info.is_private = data.get("is_private", false)
	info.room_code = data.get("room_code", "")
	info.metadata = data.get("metadata", {})
	var bd: Variant = data.get("backend_data", {})
	info.backend_data = bd.duplicate(true) if bd is Dictionary else {}
	var peers: Array = data.get("connected_peers", [])
	for p: int in peers:
		info.connected_peers.append(p)
	return info
