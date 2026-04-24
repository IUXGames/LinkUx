class_name AuthorityTransferHandler
extends RefCounted
## Handles the multi-step authority transfer protocol with locks and timeouts.

signal transfer_completed(entity_path: NodePath, new_authority: int)
signal transfer_failed(entity_path: NodePath, reason: String)

const TRANSFER_TIMEOUT_MS := 2000.0

## Active transfers: entity_path -> TransferState
var _active_transfers: Dictionary = {}


class TransferState:
	var entity_path: NodePath
	var from_peer: int
	var to_peer: int
	var started_at: int  # msec
	var locked: bool = true


func begin_transfer(entity_path: NodePath, from_peer: int, to_peer: int) -> bool:
	if _active_transfers.has(entity_path):
		transfer_failed.emit(entity_path, "Transfer already in progress")
		return false

	var state := TransferState.new()
	state.entity_path = entity_path
	state.from_peer = from_peer
	state.to_peer = to_peer
	state.started_at = Time.get_ticks_msec()
	state.locked = true
	_active_transfers[entity_path] = state
	return true


func confirm_transfer(entity_path: NodePath) -> bool:
	if not _active_transfers.has(entity_path):
		return false

	var state: TransferState = _active_transfers[entity_path]
	_active_transfers.erase(entity_path)
	transfer_completed.emit(entity_path, state.to_peer)
	return true


func cancel_transfer(entity_path: NodePath, reason: String = "Cancelled") -> void:
	if _active_transfers.has(entity_path):
		_active_transfers.erase(entity_path)
		transfer_failed.emit(entity_path, reason)


func is_locked(entity_path: NodePath) -> bool:
	if _active_transfers.has(entity_path):
		return _active_transfers[entity_path].locked
	return false


func check_timeouts() -> void:
	var now := Time.get_ticks_msec()
	var timed_out: Array[NodePath] = []

	for path: NodePath in _active_transfers:
		var state: TransferState = _active_transfers[path]
		if now - state.started_at > TRANSFER_TIMEOUT_MS:
			timed_out.append(path)

	for path: NodePath in timed_out:
		cancel_transfer(path, "Transfer timed out")


func get_pending_transfer(entity_path: NodePath) -> Dictionary:
	if _active_transfers.has(entity_path):
		var s: TransferState = _active_transfers[entity_path]
		return {"from": s.from_peer, "to": s.to_peer}
	return {}
