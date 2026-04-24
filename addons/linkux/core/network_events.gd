class_name NetworkEvents
extends Node
## Static signal bus for decoupled internal event routing.
## Subsystems emit here; the facade re-emits on its own signals.

signal session_created(session_info: Resource)
signal session_joined(session_info: Resource)
signal session_closed()
signal player_joined(player_info: Resource)
signal player_left(peer_id: int, reason: int)
signal connection_failed(error: String)
signal connection_state_changed(new_state: int)
signal scene_all_ready(scene_path: String)
signal authority_changed(entity: Node, new_authority: int)
signal global_state_changed(key: String, value: Variant)
signal network_tick(tick_number: int, delta: float)
signal protocol_version_mismatch(local_version: int, remote_version: int)
signal backend_incompatible(reason: String)
signal data_received(from_peer: int, channel: int, data: PackedByteArray)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int, reason: int)
