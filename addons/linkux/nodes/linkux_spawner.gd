@icon("res://addons/linkux/icons/Icon_LinkUxSpawner.svg")
class_name LinkUxSpawner
extends Node
## Replicated scene spawning. Handles spawning entities across all peers.
## Automatically despawns entities when their owner disconnects, and replays
## spawns for late-joining peers — no game code required for either.

@export var spawn_path: NodePath
@export var spawnable_scenes: Array[PackedScene] = []

var _logger: DebugLogger
var _sequence: int = 0
# Per-authority spawn counters — used to build collision-free spawn IDs.
# spawn_id = authority_peer * 65536 + per_authority_seq (unique within this spawner)
var _spawn_counters: Dictionary = {}
# Registry: [{spawn_id, scene_index, authority_peer, props}]
var _spawn_registry: Array[Dictionary] = []

# Transform keys that must be read live from the entity (not stored in registry)
const _DYNAMIC_KEYS := {
	"global_position": true, "global_transform": true,
	"position": true, "rotation": true, "transform": true,
}


func _ready() -> void:
	var linkux := _get_linkux()
	if linkux == null:
		return

	var events: Node = linkux.get_node_or_null("NetworkEvents")
	if events and events.has_signal("data_received"):
		events.data_received.connect(_on_data_received)

	if linkux.has_signal("player_left"):
		linkux.player_left.connect(_on_player_left)
	if linkux.has_signal("late_join_spawn_replay_needed"):
		linkux.late_join_spawn_replay_needed.connect(_on_late_join_spawn_replay_needed)


func _exit_tree() -> void:
	var linkux := _get_linkux()
	if linkux == null:
		return
	var events: Node = linkux.get_node_or_null("NetworkEvents")
	if events and events.has_signal("data_received") and events.data_received.is_connected(_on_data_received):
		events.data_received.disconnect(_on_data_received)
	if linkux.has_signal("player_left") and linkux.player_left.is_connected(_on_player_left):
		linkux.player_left.disconnect(_on_player_left)
	if linkux.has_signal("late_join_spawn_replay_needed") and linkux.late_join_spawn_replay_needed.is_connected(_on_late_join_spawn_replay_needed):
		linkux.late_join_spawn_replay_needed.disconnect(_on_late_join_spawn_replay_needed)


func spawn(scene_index: int, properties: Dictionary = {}, authority_peer: int = 1) -> Node:
	## Spawns a scene locally and replicates to all peers.
	if scene_index < 0 or scene_index >= spawnable_scenes.size():
		push_error("LinkUxSpawner: Invalid scene index %d" % scene_index)
		return null

	var scene := spawnable_scenes[scene_index]
	if scene == null:
		push_error("LinkUxSpawner: Scene at index %d is null" % scene_index)
		return null

	var instance := scene.instantiate()

	var parent := get_node_or_null(spawn_path)
	if parent == null:
		parent = get_parent()

	var linkux := _get_linkux()
	var spawn_id := _next_spawn_id(authority_peer)
	instance.set_meta("_linkux_spawn_id", spawn_id)
	if authority_peer >= 1:
		instance.set_meta("_linkux_net_entity_id", authority_peer)

	# IMPORTANT:
	# Some gameplay scripts decide "local player" in _ready() using props like `player_peer_id`.
	# If we add the node to the tree first, _ready() runs before properties are applied and the node may
	# permanently configure itself as "remote" (no camera / no input). So we apply non-transform props first.
	for key: String in properties:
		if _DYNAMIC_KEYS.has(key):
			continue
		if key in instance:
			instance.set(key, properties[key])

	parent.add_child(instance)

	# Apply transform-ish properties after the node is in the tree (needs valid parent chain)
	for key: String in properties:
		if not _DYNAMIC_KEYS.has(key):
			continue
		if key in instance:
			instance.set(key, properties[key])

	# Set authority
	if linkux and linkux.has_method("set_entity_authority"):
		linkux.set_entity_authority(instance, authority_peer)

	_register_spawn(spawn_id, scene_index, authority_peer, properties)
	_broadcast_spawn(scene_index, instance.get_path(), properties, authority_peer, authority_peer, spawn_id)

	return instance


func despawn(entity: Node) -> void:
	## Removes an entity locally and broadcasts despawn to all peers.
	var linkux := _get_linkux()
	if linkux and linkux.has_method("unregister_entity"):
		linkux.unregister_entity(entity)

	var spawn_id := int(entity.get_meta("_linkux_spawn_id", -1)) if entity.has_meta("_linkux_spawn_id") else -1
	var auth_peer := -1
	if entity != null:
		if "player_peer_id" in entity:
			auth_peer = int(entity.get("player_peer_id"))
		elif entity.has_meta("_linkux_net_entity_id"):
			auth_peer = int(entity.get_meta("_linkux_net_entity_id", -1))

	_unregister_spawn(spawn_id)
	_broadcast_despawn(entity.get_path(), auth_peer, spawn_id)
	entity.queue_free()


# ── Spawn registry ────────────────────────────────────────────────────────────

func _next_spawn_id(authority_peer: int) -> int:
	var seq: int = _spawn_counters.get(authority_peer, 0) + 1
	_spawn_counters[authority_peer] = seq
	return authority_peer * 65536 + seq


func _register_spawn(spawn_id: int, scene_index: int, authority_peer: int, props: Dictionary) -> void:
	_spawn_registry.append({
		"spawn_id": spawn_id,
		"scene_index": scene_index,
		"authority_peer": authority_peer,
		"props": props.duplicate(),
	})


func _unregister_spawn(spawn_id: int) -> void:
	if spawn_id < 1:
		return
	_spawn_registry = _spawn_registry.filter(func(e: Dictionary) -> bool:
		return e.get("spawn_id", -1) != spawn_id
	)


func _unregister_spawns_by_authority(authority_peer: int) -> void:
	if authority_peer < 1:
		return
	_spawn_registry = _spawn_registry.filter(func(e: Dictionary) -> bool:
		return e.authority_peer != authority_peer
	)


# ── Automatic disconnect cleanup ──────────────────────────────────────────────

func _on_player_left(peer_id: int, _reason: int) -> void:
	## Host only: despawn all entities owned by the disconnected peer.
	var linkux := _get_linkux()
	if linkux == null or not linkux.has_method("is_host") or not linkux.is_host():
		return
	var to_despawn: Array[Node] = []
	for entry: Dictionary in _spawn_registry:
		if entry.authority_peer != peer_id:
			continue
		var entity := _find_entity_by_spawn_id(entry.get("spawn_id", -1))
		if entity:
			to_despawn.append(entity)
	for entity in to_despawn:
		despawn(entity)


# ── Automatic late-join replay ────────────────────────────────────────────────

func _on_late_join_spawn_replay_needed(joining_peer_id: int) -> void:
	## Host only: unicast all currently spawned entities to the newly joined peer.
	var linkux := _get_linkux()
	if linkux == null or not linkux.has_method("is_host") or not linkux.is_host():
		return

	for entry: Dictionary in _spawn_registry:
		var auth_peer: int = entry.authority_peer
		if auth_peer == joining_peer_id:
			continue

		var props: Dictionary = entry.props.duplicate()
		var spawn_id: int = entry.get("spawn_id", -1)

		# Override stored transform with live values from the entity
		var entity := _find_entity_by_spawn_id(spawn_id)
		if entity == null:
			continue
		for key: String in _DYNAMIC_KEYS:
			if key in entity:
				props[key] = entity.get(key)

		unicast_spawn_to_peer(entry.scene_index, props, auth_peer, joining_peer_id, spawn_id)


# ── Network messaging ─────────────────────────────────────────────────────────

func _broadcast_spawn(scene_index: int, entity_path: NodePath, properties: Dictionary, authority_peer: int, net_entity_id: int = -1, spawn_id: int = -1) -> void:
	var linkux := _get_linkux()
	if linkux == null:
		return

	var transport: Node = linkux.get_node_or_null("TransportLayer")
	if transport == null or not transport.has_method("broadcast"):
		return

	_sequence = (_sequence + 1) % 256
	var payload := {
		"scene_index": scene_index,
		"entity_path": str(entity_path),
		"properties": properties,
		"authority_peer": authority_peer,
		"spawner_path": str(get_path()),
		"net_entity_id": net_entity_id,
		"spawn_id": spawn_id,
	}
	var data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.ENTITY_SPAWNED, 0, _sequence, payload
	)
	transport.broadcast(data, NetworkEnums.ChannelType.CONTROL, true)


func unicast_spawn_to_peer(scene_index: int, properties: Dictionary, authority_peer: int, target_peer: int, spawn_id: int = -1) -> void:
	## Unicasts a spawn to a single peer (used for late-join replay).
	var linkux := _get_linkux()
	if linkux == null:
		return
	var transport: Node = linkux.get_node_or_null("TransportLayer")
	if transport == null or not transport.has_method("send"):
		return
	_sequence = (_sequence + 1) % 256
	var payload := {
		"scene_index": scene_index,
		"entity_path": "",
		"properties": properties,
		"authority_peer": authority_peer,
		"spawner_path": str(get_path()),
		"net_entity_id": authority_peer,
		"spawn_id": spawn_id,
	}
	var data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.ENTITY_SPAWNED, 0, _sequence, payload
	)
	transport.send(target_peer, data, NetworkEnums.ChannelType.CONTROL, true)


func _broadcast_despawn(entity_path: NodePath, authority_peer: int = -1, spawn_id: int = -1) -> void:
	var linkux := _get_linkux()
	if linkux == null:
		return

	var transport: Node = linkux.get_node_or_null("TransportLayer")
	if transport == null or not transport.has_method("broadcast"):
		return

	_sequence = (_sequence + 1) % 256
	var payload := {
		"entity_path": str(entity_path),
		"spawner_path": str(get_path()),
		"authority_peer": authority_peer,
		"spawn_id": spawn_id,
	}
	var data := MessageSerializer.serialize_message(
		NetworkEnums.MessageType.ENTITY_DESPAWNED, 0, _sequence, payload
	)
	transport.broadcast(data, NetworkEnums.ChannelType.CONTROL, true)


func _on_data_received(from_peer: int, _channel: int, data: PackedByteArray) -> void:
	if data.size() < MessageSerializer.HEADER_SIZE:
		return

	var header := MessageSerializer.deserialize_header(data)
	var msg_type: int = header.get("type", -1)

	match msg_type:
		NetworkEnums.MessageType.ENTITY_SPAWNED:
			_handle_remote_spawn(data, from_peer)
		NetworkEnums.MessageType.ENTITY_DESPAWNED:
			_handle_remote_despawn(data, from_peer)


func _handle_remote_spawn(data: PackedByteArray, from_peer: int = 0) -> void:
	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return

	# Only handle spawns from our spawner
	var spawner_path: String = payload.get("spawner_path", "")
	if spawner_path != str(get_path()):
		return

	var scene_index: int = payload.get("scene_index", -1)
	if scene_index < 0 or scene_index >= spawnable_scenes.size():
		return

	var scene := spawnable_scenes[scene_index]
	if scene == null:
		return

	var authority_peer: int = int(payload.get("authority_peer", 1))
	var spawn_id: int = int(payload.get("spawn_id", -1))

	# Sync the per-authority counter so our own future spawn_ids stay ahead
	if spawn_id >= 1:
		var seq: int = spawn_id & 0xFFFF
		_spawn_counters[authority_peer] = maxi(_spawn_counters.get(authority_peer, 0), seq)

	var linkux := _get_linkux()
	var parent_check := get_node_or_null(spawn_path)
	if parent_check == null:
		parent_check = get_parent()

	# Remove duplicate: same spawn_id OR same player_peer_id (out-of-order packets)
	for existing in parent_check.get_children():
		var is_dup := false
		if spawn_id >= 1 and existing.has_meta("_linkux_spawn_id") and int(existing.get_meta("_linkux_spawn_id")) == spawn_id:
			is_dup = true
		elif "player_peer_id" in existing and int(existing.get("player_peer_id")) == authority_peer:
			is_dup = true
		if is_dup:
			var old_spawn_id := int(existing.get_meta("_linkux_spawn_id", -1)) if existing.has_meta("_linkux_spawn_id") else -1
			if linkux and linkux.has_method("unregister_entity"):
				linkux.unregister_entity(existing)
			_unregister_spawn(old_spawn_id)
			existing.queue_free()
			break

	var instance := scene.instantiate()
	var properties: Dictionary = payload.get("properties", {})

	var net_entity_id: int = int(payload.get("net_entity_id", -1))
	if net_entity_id < 1:
		net_entity_id = authority_peer
	if spawn_id >= 1:
		instance.set_meta("_linkux_spawn_id", spawn_id)
	if net_entity_id >= 1:
		instance.set_meta("_linkux_net_entity_id", net_entity_id)

	# Apply non-transform props before add_child so _ready() sees correct values (e.g. player_peer_id).
	for key: String in properties:
		if _DYNAMIC_KEYS.has(key):
			continue
		if key in instance:
			instance.set(key, properties[key])

	var parent := get_node_or_null(spawn_path)
	if parent == null:
		parent = get_parent()
	parent.add_child(instance)

	for key: String in properties:
		if not _DYNAMIC_KEYS.has(key):
			continue
		if key in instance:
			instance.set(key, properties[key])

	if linkux and linkux.has_method("set_entity_authority"):
		linkux.set_entity_authority(instance, authority_peer)

	_register_spawn(spawn_id, scene_index, authority_peer, properties)

	# In ENet star topology clients only connect to the host, so their spawn
	# broadcasts never reach other clients. The host relays each client spawn
	# to all remaining peers so every machine sees a consistent world.
	if linkux and linkux.is_host() and from_peer > 1:
		var transport: Node = linkux.get_node_or_null("TransportLayer")
		if transport and transport.has_method("send"):
			for peer_id: int in linkux.get_connected_peers():
				if peer_id != from_peer:
					transport.send(peer_id, data, NetworkEnums.ChannelType.CONTROL, true)


func _handle_remote_despawn(data: PackedByteArray, _from_peer: int = 0) -> void:
	var payload: Variant = MessageSerializer.deserialize_payload(data)
	if not payload is Dictionary:
		return

	var spawner_path: String = payload.get("spawner_path", "")
	if spawner_path != str(get_path()):
		return

	var spawn_id: int = int(payload.get("spawn_id", -1))
	var entity: Node = null

	if spawn_id >= 1:
		entity = _find_entity_by_spawn_id(spawn_id)

	if entity == null:
		# Fallback: try path, then authority peer
		var entity_path := NodePath(payload.get("entity_path", ""))
		entity = get_node_or_null(entity_path)
		var auth_peer: int = int(payload.get("authority_peer", -1))
		if entity == null and auth_peer >= 1:
			entity = _find_entity_by_authority_first(auth_peer)

	if entity:
		var linkux := _get_linkux()
		if linkux and linkux.has_method("unregister_entity"):
			linkux.unregister_entity(entity)
		_unregister_spawn(spawn_id)
		entity.queue_free()


# ── Entity lookup ─────────────────────────────────────────────────────────────

func _find_entity_by_spawn_id(spawn_id: int) -> Node:
	if spawn_id < 1:
		return null
	var parent := get_node_or_null(spawn_path)
	if parent == null:
		parent = get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child.has_meta("_linkux_spawn_id") and int(child.get_meta("_linkux_spawn_id")) == spawn_id:
			return child
	return null


func _find_entity_by_authority_first(authority_peer: int) -> Node:
	## Returns the first entity owned by authority_peer (fallback for legacy despawn).
	var parent := get_node_or_null(spawn_path)
	if parent == null:
		parent = get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if "player_peer_id" in child and int(child.get("player_peer_id")) == authority_peer:
			return child
		if child.has_meta("_linkux_net_entity_id") and int(child.get_meta("_linkux_net_entity_id")) == authority_peer:
			return child
	return null


func _get_linkux() -> Node:
	return get_tree().root.get_node_or_null("LinkUx")
