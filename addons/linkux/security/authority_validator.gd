class_name AuthorityValidator
extends RefCounted
## Validates authority requests and changes on the host side.

static func can_request_authority(entity_path: NodePath, requesting_peer: int, current_authority: int, mode: int, is_locked: bool) -> bool:
	if is_locked:
		return false

	match mode:
		NetworkEnums.AuthorityMode.HOST:
			# Only host (peer 1) can hold authority in HOST mode
			return requesting_peer == 1
		NetworkEnums.AuthorityMode.OWNER:
			# Owner mode — only the original owner can reclaim
			return true
		NetworkEnums.AuthorityMode.TRANSFERABLE:
			# Anyone can request if not locked
			return true
		_:
			return false


static func can_transfer_authority(entity_path: NodePath, from_peer: int, to_peer: int, current_authority: int, is_locked: bool) -> bool:
	if is_locked:
		return false
	# Only current authority or host can initiate transfer
	if from_peer != current_authority and from_peer != 1:
		return false
	return to_peer > 0
