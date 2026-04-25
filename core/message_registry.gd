class_name MessageRegistry
extends RefCounted
## Centralized registry for message types. Validates message IDs and provides
## lookup utilities to prevent collisions and ensure consistency.

## Maps MessageType int -> human-readable name for debug logging.
var _type_names: Dictionary = {}

## Set of all registered type IDs for collision detection.
var _registered_ids: Dictionary = {}


func _init() -> void:
	_register_builtin_types()


func _register_builtin_types() -> void:
	var enum_values := {
		NetworkEnums.MessageType.STATE_FULL: "STATE_FULL",
		NetworkEnums.MessageType.STATE_DELTA: "STATE_DELTA",
		NetworkEnums.MessageType.GLOBAL_STATE_UPDATE: "GLOBAL_STATE_UPDATE",
		NetworkEnums.MessageType.GLOBAL_STATE_REQUEST: "GLOBAL_STATE_REQUEST",
		NetworkEnums.MessageType.RPC_RELIABLE: "RPC_RELIABLE",
		NetworkEnums.MessageType.RPC_UNRELIABLE: "RPC_UNRELIABLE",
		NetworkEnums.MessageType.AUTH_REQUEST: "AUTH_REQUEST",
		NetworkEnums.MessageType.AUTH_TRANSFER_BEGIN: "AUTH_TRANSFER_BEGIN",
		NetworkEnums.MessageType.AUTH_TRANSFER_ACK: "AUTH_TRANSFER_ACK",
		NetworkEnums.MessageType.AUTH_CHANGED: "AUTH_CHANGED",
		NetworkEnums.MessageType.AUTH_LOCKED: "AUTH_LOCKED",
		NetworkEnums.MessageType.AUTH_DENIED: "AUTH_DENIED",
		NetworkEnums.MessageType.SCENE_LOAD_REQUEST: "SCENE_LOAD_REQUEST",
		NetworkEnums.MessageType.SCENE_READY_REPORT: "SCENE_READY_REPORT",
		NetworkEnums.MessageType.SCENE_ALL_READY: "SCENE_ALL_READY",
		NetworkEnums.MessageType.WORLD_SNAPSHOT: "WORLD_SNAPSHOT",
		NetworkEnums.MessageType.WORLD_SNAPSHOT_CHUNK: "WORLD_SNAPSHOT_CHUNK",
		NetworkEnums.MessageType.WORLD_SNAPSHOT_ACK: "WORLD_SNAPSHOT_ACK",
		NetworkEnums.MessageType.HEARTBEAT: "HEARTBEAT",
		NetworkEnums.MessageType.HEARTBEAT_ACK: "HEARTBEAT_ACK",
		NetworkEnums.MessageType.DISCONNECT_NOTICE: "DISCONNECT_NOTICE",
		NetworkEnums.MessageType.PROTOCOL_HANDSHAKE: "PROTOCOL_HANDSHAKE",
		NetworkEnums.MessageType.ENTITY_REGISTER: "ENTITY_REGISTER",
		NetworkEnums.MessageType.ENTITY_UNREGISTER: "ENTITY_UNREGISTER",
		NetworkEnums.MessageType.ENTITY_PATH_MAP: "ENTITY_PATH_MAP",
		NetworkEnums.MessageType.ENTITY_SPAWNED: "ENTITY_SPAWNED",
		NetworkEnums.MessageType.ENTITY_DESPAWNED: "ENTITY_DESPAWNED",
	}

	for id: int in enum_values:
		_type_names[id] = enum_values[id]
		_registered_ids[id] = true


func is_valid_type(type_id: int) -> bool:
	return _registered_ids.has(type_id)


func get_type_name(type_id: int) -> String:
	if _type_names.has(type_id):
		return _type_names[type_id]
	return "UNKNOWN(0x%02X)" % type_id


func register_custom_type(type_id: int, type_name: String) -> bool:
	if _registered_ids.has(type_id):
		push_error("LinkUx: MessageRegistry collision — ID 0x%02X already registered as '%s'" % [type_id, _type_names.get(type_id, "UNKNOWN")])
		return false
	_type_names[type_id] = type_name
	_registered_ids[type_id] = true
	return true
