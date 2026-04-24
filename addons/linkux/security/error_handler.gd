class_name LinkUxErrorHandler
extends RefCounted
## Standardized error handling with error codes and recovery strategies.


static func get_error_message(code: int) -> String:
	match code:
		NetworkEnums.ErrorCode.SUCCESS:
			return "Success"
		NetworkEnums.ErrorCode.NETWORK_UNAVAILABLE:
			return "Network is unavailable"
		NetworkEnums.ErrorCode.SESSION_NOT_FOUND:
			return "Session not found"
		NetworkEnums.ErrorCode.SESSION_FULL:
			return "Session is full"
		NetworkEnums.ErrorCode.AUTHORITY_DENIED:
			return "Authority request denied"
		NetworkEnums.ErrorCode.AUTHORITY_TRANSFER_FAILED:
			return "Authority transfer failed"
		NetworkEnums.ErrorCode.PROTOCOL_VERSION_MISMATCH:
			return "Protocol version mismatch"
		NetworkEnums.ErrorCode.BACKEND_INCOMPATIBLE:
			return "Backend incompatible"
		NetworkEnums.ErrorCode.SERIALIZATION_FAILED:
			return "Serialization failed"
		NetworkEnums.ErrorCode.PACKET_VALIDATION_FAILED:
			return "Packet validation failed"
		NetworkEnums.ErrorCode.RATE_LIMIT_EXCEEDED:
			return "Rate limit exceeded"
		NetworkEnums.ErrorCode.HEARTBEAT_TIMEOUT:
			return "Heartbeat timeout"
		NetworkEnums.ErrorCode.INVALID_STATE_TRANSITION:
			return "Invalid state transition"
		NetworkEnums.ErrorCode.BACKEND_NOT_SET:
			return "No backend configured"
		NetworkEnums.ErrorCode.ALREADY_IN_SESSION:
			return "Already in a session"
		NetworkEnums.ErrorCode.NOT_HOST:
			return "Operation requires host privileges"
		NetworkEnums.ErrorCode.ENTITY_NOT_REGISTERED:
			return "Entity is not registered for replication"
		_:
			return "Unknown error (%d)" % code


static func is_recoverable(code: int) -> bool:
	match code:
		NetworkEnums.ErrorCode.NETWORK_UNAVAILABLE, \
		NetworkEnums.ErrorCode.SESSION_NOT_FOUND, \
		NetworkEnums.ErrorCode.SESSION_FULL, \
		NetworkEnums.ErrorCode.HEARTBEAT_TIMEOUT, \
		NetworkEnums.ErrorCode.RATE_LIMIT_EXCEEDED:
			return true
		_:
			return false


static func get_recovery_hint(code: int) -> String:
	match code:
		NetworkEnums.ErrorCode.NETWORK_UNAVAILABLE:
			return "Check network connection and retry"
		NetworkEnums.ErrorCode.SESSION_NOT_FOUND:
			return "Refresh session list and try again"
		NetworkEnums.ErrorCode.SESSION_FULL:
			return "Wait for a slot or find another session"
		NetworkEnums.ErrorCode.HEARTBEAT_TIMEOUT:
			return "Attempting reconnection"
		NetworkEnums.ErrorCode.RATE_LIMIT_EXCEEDED:
			return "Reduce send frequency"
		_:
			return ""
