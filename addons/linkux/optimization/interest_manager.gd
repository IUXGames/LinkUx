class_name InterestManager
extends Node
## Filters which entities are relevant to which peers based on distance or area.
## Connected to StateReplicator to skip irrelevant updates.

var _logger: DebugLogger

## Interest areas per peer: peer_id -> Variant (Rect2 for 2D, AABB for 3D)
var _peer_interest_areas: Dictionary = {}

## Entity interest areas: NodePath -> Variant (Rect2 or AABB)
var _entity_areas: Dictionary = {}

## Entity positions cache: NodePath -> Variant (Vector2 or Vector3)
var _entity_positions: Dictionary = {}


func setup(logger: DebugLogger) -> void:
	_logger = logger


func set_interest_area(entity: Node, area: Variant) -> void:
	## Set the interest/relevance area for an entity.
	_entity_areas[entity.get_path()] = area


func set_peer_interest_area(peer_id: int, area: Variant) -> void:
	## Set the area-of-interest for a peer (typically their camera/viewport).
	_peer_interest_areas[peer_id] = area


func update_entity_position(entity_path: NodePath, position: Variant) -> void:
	_entity_positions[entity_path] = position


func is_relevant(entity_path: NodePath, peer_id: int) -> bool:
	## Check if an entity is relevant to a specific peer.
	## Returns true if no filtering is configured (default: everything is relevant).
	if not _peer_interest_areas.has(peer_id):
		return true

	var peer_area: Variant = _peer_interest_areas[peer_id]
	var entity_pos: Variant = _entity_positions.get(entity_path, null)

	if entity_pos == null:
		return true  # No position data — assume relevant

	# 2D check
	if peer_area is Rect2 and entity_pos is Vector2:
		return peer_area.has_point(entity_pos)

	# 3D check
	if peer_area is AABB and entity_pos is Vector3:
		return peer_area.has_point(entity_pos)

	# Entity has its own area
	if _entity_areas.has(entity_path):
		var ent_area: Variant = _entity_areas[entity_path]
		if peer_area is Rect2 and ent_area is Rect2:
			return peer_area.intersects(ent_area)
		if peer_area is AABB and ent_area is AABB:
			return peer_area.intersects(ent_area)

	return true


func get_relevant_peers(entity_path: NodePath, all_peers: Array[int]) -> Array[int]:
	## Returns which peers should receive updates for this entity.
	var relevant: Array[int] = []
	for peer_id: int in all_peers:
		if is_relevant(entity_path, peer_id):
			relevant.append(peer_id)
	return relevant


func remove_peer(peer_id: int) -> void:
	_peer_interest_areas.erase(peer_id)


func remove_entity(entity_path: NodePath) -> void:
	_entity_areas.erase(entity_path)
	_entity_positions.erase(entity_path)


func clear() -> void:
	_peer_interest_areas.clear()
	_entity_areas.clear()
	_entity_positions.clear()
