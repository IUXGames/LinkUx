class_name SessionAdapter
extends Node
## Translates backend-specific session data into unified SessionInfo.

var _logger: DebugLogger


func setup(logger: DebugLogger) -> void:
	_logger = logger


static func from_lan_data(ip: String, port: int, session_name: String, current_players: int, max_players: int, metadata: Dictionary = {}, room_code: String = "") -> SessionInfo:
	var info := SessionInfo.new()
	info.session_id = "%s:%d" % [ip, port]
	info.session_name = session_name
	info.current_players = current_players
	info.max_players = max_players
	info.room_code = room_code
	info.metadata = metadata
	info.backend_data = {
		"ip": ip,
		"port": port,
		"backend_type": NetworkEnums.BackendType.LAN,
	}
	return info
