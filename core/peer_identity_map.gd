class_name PeerIdentityMap
extends RefCounted
## Normalizes peer identities across different backends.
## Different backends can assign different kinds of IDs — this maps them to
## unified LinkUx peer IDs used throughout the public API.

## Maps backend-specific ID (String) -> LinkUx peer ID (int).
var _backend_to_linkux: Dictionary = {}

## Maps LinkUx peer ID (int) -> backend-specific ID (String).
var _linkux_to_backend: Dictionary = {}

## Maps LinkUx peer ID (int) -> display name.
var _display_names: Dictionary = {}

## Next auto-assigned LinkUx peer ID (host is always 1).
var _next_id: int = 2


func register_host(backend_id: String, display_name: String = "Host") -> int:
	var linkux_id := 1
	_backend_to_linkux[backend_id] = linkux_id
	_linkux_to_backend[linkux_id] = backend_id
	_display_names[linkux_id] = display_name
	return linkux_id


func register_peer(backend_id: String, display_name: String = "") -> int:
	if _backend_to_linkux.has(backend_id):
		return _backend_to_linkux[backend_id]

	var linkux_id := _next_id
	_next_id += 1
	_backend_to_linkux[backend_id] = linkux_id
	_linkux_to_backend[linkux_id] = backend_id
	_display_names[linkux_id] = display_name if display_name != "" else "Peer_%d" % linkux_id
	return linkux_id


func register_peer_with_id(linkux_id: int, backend_id: String, display_name: String = "") -> void:
	_backend_to_linkux[backend_id] = linkux_id
	_linkux_to_backend[linkux_id] = backend_id
	_display_names[linkux_id] = display_name if display_name != "" else "Peer_%d" % linkux_id
	if linkux_id >= _next_id:
		_next_id = linkux_id + 1


func get_linkux_id(backend_id: String) -> int:
	return _backend_to_linkux.get(backend_id, -1)


func get_backend_id(linkux_id: int) -> String:
	return _linkux_to_backend.get(linkux_id, "")


func get_display_name(linkux_id: int) -> String:
	return _display_names.get(linkux_id, "")


func unregister_peer(linkux_id: int) -> void:
	var backend_id: String = _linkux_to_backend.get(linkux_id, "")
	if backend_id != "":
		_backend_to_linkux.erase(backend_id)
	_linkux_to_backend.erase(linkux_id)
	_display_names.erase(linkux_id)


func get_all_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in _linkux_to_backend:
		ids.append(id)
	return ids


func clear() -> void:
	_backend_to_linkux.clear()
	_linkux_to_backend.clear()
	_display_names.clear()
	_next_id = 2
