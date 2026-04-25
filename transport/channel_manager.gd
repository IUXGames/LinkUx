class_name ChannelManager
extends RefCounted
## Maps LinkUx logical channels to backend-specific channel IDs.

## Standard channel assignments.
const CHANNEL_RPC := NetworkEnums.ChannelType.RPC
const CHANNEL_STATE := NetworkEnums.ChannelType.STATE
const CHANNEL_CONTROL := NetworkEnums.ChannelType.CONTROL

## Backend channel mapping (can be overridden per-backend).
var _channel_map: Dictionary = {
	CHANNEL_RPC: 0,
	CHANNEL_STATE: 1,
	CHANNEL_CONTROL: 2,
}


func get_backend_channel(linkux_channel: int) -> int:
	return _channel_map.get(linkux_channel, 0)


func set_channel_mapping(linkux_channel: int, backend_channel: int) -> void:
	_channel_map[linkux_channel] = backend_channel


func get_channel_name(channel: int) -> String:
	match channel:
		CHANNEL_RPC: return "RPC"
		CHANNEL_STATE: return "STATE"
		CHANNEL_CONTROL: return "CONTROL"
		_: return "UNKNOWN(%d)" % channel
