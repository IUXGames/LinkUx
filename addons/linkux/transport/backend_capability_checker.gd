class_name BackendCapabilityChecker
extends RefCounted
## Validates that a backend supports the required features before session start.

static func check_required_capabilities(backend: NetworkBackend) -> Dictionary:
	## Returns {"ok": bool, "missing": Array[String]}
	var caps: Dictionary = backend._backend_get_capabilities()
	var missing: Array[String] = []

	# These are hard requirements
	var required_keys := ["supports_late_join", "supports_authority_transfer", "max_packet_size"]
	for key: String in required_keys:
		if not caps.has(key):
			missing.append(key)

	return {
		"ok": missing.is_empty(),
		"missing": missing,
		"capabilities": caps,
	}


static func supports_feature(backend: NetworkBackend, feature: String) -> bool:
	var caps: Dictionary = backend._backend_get_capabilities()
	return caps.get(feature, false) == true
