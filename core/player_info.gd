class_name PlayerInfo
extends Resource
## Unified player data structure used across all backends.

@export var peer_id: int = -1
@export var display_name: String = ""
@export var is_host: bool = false
@export var metadata: Dictionary = {}
@export var data: Dictionary = {}


func _to_string() -> String:
	var role := "Host" if is_host else "Client"
	return "PlayerInfo<%d | %s | %s>" % [peer_id, display_name, role]


func to_dict() -> Dictionary:
	return {
		"peer_id": peer_id,
		"display_name": display_name,
		"is_host": is_host,
		"metadata": metadata,
		"data": data,
	}


static func from_dict(data: Dictionary) -> PlayerInfo:
	var info := PlayerInfo.new()
	info.peer_id = data.get("peer_id", -1)
	info.display_name = data.get("display_name", "")
	info.is_host = data.get("is_host", false)
	info.metadata = data.get("metadata", {})
	info.data = data.get("data", {})
	return info


func set_name(name: String) -> void:
	display_name = name


func get_name() -> String:
	return display_name


func set_data_value(key: String, value: Variant) -> void:
	data[key] = value


func get_data_value(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)


func erase_data_value(key: String) -> void:
	data.erase(key)
