class_name ProtocolVersion
extends RefCounted
## Protocol version management. Ensures connecting peers share compatible protocols.

const CURRENT_VERSION := 1
const MIN_COMPATIBLE_VERSION := 1


static func get_version() -> int:
	return CURRENT_VERSION


static func is_compatible(remote_version: int) -> bool:
	return remote_version >= MIN_COMPATIBLE_VERSION and remote_version <= CURRENT_VERSION


static func create_handshake_payload() -> Dictionary:
	var cfg := ConfigFile.new()
	var addon_version := "unknown"
	if cfg.load("res://addons/linkux/plugin.cfg") == OK:
		addon_version = cfg.get_value("plugin", "version", "unknown")
	return {
		"protocol_version": CURRENT_VERSION,
		"addon_version": addon_version,
	}


static func validate_handshake(payload: Dictionary) -> bool:
	if not payload.has("protocol_version"):
		return false
	return is_compatible(payload["protocol_version"] as int)
