@icon("res://addons/linkux/icons/Icon_LinkUxEntity.svg")
class_name LinkUxEntity
extends Node
## Attach as a child of any node to make it a replicated entity.
## Automatically registers/unregisters with the StateReplicator.

@export var authority_mode: NetworkEnums.AuthorityMode = NetworkEnums.AuthorityMode.HOST
@export var replicated_properties: PackedStringArray = []
@export var replication_mode: NetworkEnums.ReplicationMode = NetworkEnums.ReplicationMode.ON_CHANGE


func _ready() -> void:
	# Defer to ensure LinkUx autoload is available
	call_deferred("_register")


func _exit_tree() -> void:
	var target := get_parent()
	if target == null:
		return
	var linkux := _get_linkux()
	if linkux and linkux.has_method("unregister_entity"):
		linkux.unregister_entity(target)


func _register() -> void:
	var target := get_parent()
	if target == null:
		push_warning("LinkUxEntity: No parent node to register")
		return

	var linkux := _get_linkux()
	if linkux == null:
		push_warning("LinkUxEntity: LinkUx autoload not found")
		return

	if not linkux.has_method("is_in_session"):
		return

	if linkux.is_in_session():
		var props: Array[String] = []
		for p: String in replicated_properties:
			props.append(p)
		linkux.register_entity(target, props, replication_mode)

		var auth_manager := linkux.get_node_or_null("AuthorityManager") as AuthorityManager
		if auth_manager:
			var peer_for_authority := 1
			match authority_mode:
				NetworkEnums.AuthorityMode.HOST, NetworkEnums.AuthorityMode.TRANSFERABLE:
					peer_for_authority = 1
				NetworkEnums.AuthorityMode.OWNER:
					peer_for_authority = linkux.get_local_peer_id() if linkux.has_method("get_local_peer_id") else 1
			auth_manager.set_authority(target, peer_for_authority, authority_mode)


func _get_linkux() -> Node:
	return get_tree().root.get_node_or_null("LinkUx")
