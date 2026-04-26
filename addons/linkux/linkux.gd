extends Node
## LinkUx — Universal multiplayer abstraction layer.
## This is the single public API surface. All game code interacts with this Autoload.

# ── Public Signals ───────────────────────────────────────────────────────────

signal session_created(session_info: SessionInfo)
signal session_joined(session_info: SessionInfo)
signal session_closed()
signal player_joined(player_info: PlayerInfo)
signal player_left(peer_id: int, reason: int)
signal player_left_processed(player_info: PlayerInfo, reason: int)
signal connection_failed(error: String)
signal connection_state_changed(new_state: int)
signal session_started()
signal session_ended()
signal scene_all_ready(scene_path: String)
signal scene_load_requested(scene_path: String)
signal authority_changed(entity: Node, new_authority: int)
signal global_state_changed(key: String, value: Variant)
signal network_tick(tick_number: int, delta: float)
signal protocol_version_mismatch(local_version: int, remote_version: int)
signal backend_incompatible(reason: String)
## Centralized internal log feed for UI / gameplay.
signal feedback_log_added(entry: Dictionary)
signal player_updated(player_info: PlayerInfo)
## Host only. A peer late-joined and finished loading the level: replay spawns of existing entities before the world snapshot.
signal late_join_spawn_replay_needed(peer_id: int)


# ── Internal References ──────────────────────────────────────────────────────

var _config: LinkUxConfig
var _logger := DebugLogger.new()
var _debug_hooks := DebugHooks.new()
var _events: NetworkEvents
var _state_machine: InternalStateMachine
var _message_registry := MessageRegistry.new()
var _peer_identity_map := PeerIdentityMap.new()

# Subsystems (child nodes)
var _tick_manager: Node  # TickManager
var _session_manager: Node  # SessionManager
var _authority_manager: Node  # AuthorityManager
var _state_replicator: Node  # StateReplicator
var _rpc_relay: Node  # RpcRelay
var _scene_sync: Node  # SceneSync
var _disconnect_handler: Node  # DisconnectHandler
var _late_join_handler: Node  # LateJoinHandler
var _interest_manager: Node  # InterestManager
var _transport_layer: TransportLayer

# Backend
var _active_backend: NetworkBackend
var _backend_type: int = NetworkEnums.BackendType.NONE

# Steam
var _steam_initialized: bool = false

## LAN uses custom binary packets on ENet; disable SceneTree's MultiplayerAPI poll so the engine does not try to decode them as Godot RPCs.
var _scene_tree_multiplayer_poll_saved: bool = true
var _scene_tree_multiplayer_poll_overridden: bool = false

# Players
var _players: Dictionary = {}  # peer_id -> PlayerInfo
var _current_session: SessionInfo
var _feedback_logs: Array[Dictionary] = []
var _feedback_log_max_entries: int = 500
var _local_player_profile: Dictionary = {"display_name": "Player", "metadata": {}, "data": {}}


func _ready() -> void:
	_state_machine = InternalStateMachine.new(_logger)
	_events = $NetworkEvents as NetworkEvents

	# Wire internal events to public signals and lifecycle handlers
	_events.session_created.connect(func(info: Resource) -> void:
		session_created.emit(info)
		_on_session_created(info as SessionInfo)
	)
	_events.session_joined.connect(func(info: Resource) -> void:
		session_joined.emit(info)
		_on_session_joined(info as SessionInfo)
	)
	_events.session_closed.connect(func() -> void: session_closed.emit())
	_events.player_joined.connect(func(info: Resource) -> void:
		player_joined.emit(info)
		_on_player_joined(info as PlayerInfo)
	)
	_events.player_left.connect(func(pid: int, reason: int) -> void:
		player_left.emit(pid, reason)
		_on_player_left(pid, reason)
	)
	_events.connection_failed.connect(func(err: String) -> void:
		_on_connection_failed_reset_state(err)
		connection_failed.emit(err)
	)
	_events.connection_state_changed.connect(func(s: int) -> void: connection_state_changed.emit(s))
	_events.scene_all_ready.connect(func(path: String) -> void:
		scene_all_ready.emit(path)
		_on_scene_all_ready(path)
	)
	_events.authority_changed.connect(func(e: Node, a: int) -> void: authority_changed.emit(e, a))
	_events.global_state_changed.connect(func(k: String, v: Variant) -> void: global_state_changed.emit(k, v))
	_events.network_tick.connect(func(t: int, d: float) -> void: network_tick.emit(t, d))
	_events.protocol_version_mismatch.connect(func(l: int, r: int) -> void: protocol_version_mismatch.emit(l, r))
	_events.backend_incompatible.connect(func(r: String) -> void: backend_incompatible.emit(r))

	# Grab subsystem references from child nodes
	_tick_manager = $TickManager
	_session_manager = $SessionManager
	_authority_manager = $AuthorityManager
	_state_replicator = $StateReplicator
	_rpc_relay = $RpcRelay
	_scene_sync = $SceneSync
	_disconnect_handler = $DisconnectHandler
	_late_join_handler = $LateJoinHandler
	_interest_manager = $InterestManager
	_transport_layer = $TransportLayer

	if _scene_sync.has_signal("scene_load_requested"):
		_scene_sync.scene_load_requested.connect(func(p: String) -> void: scene_load_requested.emit(p))
	if _logger.has_signal("log_emitted") and not _logger.log_emitted.is_connected(_on_logger_log_emitted):
		_logger.log_emitted.connect(_on_logger_log_emitted)

	_logger.info("LinkUx ready (protocol v%d)" % ProtocolVersion.get_version(), "Core")


# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

func initialize(config: LinkUxConfig = null) -> int:
	await LinkUx.ready
	_config = config if config else LinkUxConfig.new()
	if not _config.network: _config.network = NetworkConfig.new()
	if not _config.lan: _config.lan = LanBackendConfig.new()
	if not _config.advanced: _config.advanced = AdvancedConfig.new()

	_logger.set_log_level(_config.log_level)
	_debug_hooks.enabled = _config.debug_enabled

	# Setup backend (only if one was explicitly configured)
	if _config.default_backend != NetworkEnums.BackendType.NONE:
		set_backend(_config.default_backend)

	# Initialize subsystems
	_tick_manager.setup(_config.network, _events, _logger, _debug_hooks)
	_session_manager.setup(_active_backend, _events, _logger, _peer_identity_map)
	_rpc_relay.setup(_transport_layer, _events, _logger, _config.network)
	_state_replicator.setup(_transport_layer, _events, _logger, _config.network, _debug_hooks)
	_authority_manager.setup(_transport_layer, _events, _logger)
	_scene_sync.setup(_transport_layer, _events, _logger)
	_disconnect_handler.setup(_transport_layer, _events, _logger, _config.network, _config.advanced)
	_late_join_handler.setup(_transport_layer, _events, _logger, _state_replicator, _authority_manager)
	_interest_manager.setup(_logger)

	# Wire tick to subsystems
	if _tick_manager.network_tick.is_connected(_on_network_tick):
		_tick_manager.network_tick.disconnect(_on_network_tick)
	_tick_manager.network_tick.connect(_on_network_tick)

	## Idempotent: the menu may leave the machine already in READY (e.g. `prepare_for_new_session` / shutdown); READY→READY is invalid.
	if not _state_machine.is_state(NetworkEnums.InternalState.READY):
		if not _state_machine.transition_to(NetworkEnums.InternalState.READY):
			return NetworkEnums.ErrorCode.INVALID_STATE_TRANSITION

	_register_internal_rpc_handlers()

	_logger.info("Initialized with backend: %s" % _get_backend_name(), "Core")
	return NetworkEnums.ErrorCode.SUCCESS


func set_backend(backend_type: int) -> void:
	_restore_scene_tree_multiplayer_poll()

	_backend_type = backend_type

	# Remove old backend if exists — call shutdown first so signals/connections are cleaned up
	# synchronously before the new backend is created (queue_free defers the actual deletion).
	if _active_backend:
		_active_backend._backend_shutdown()
		_active_backend.queue_free()
		_active_backend = null

	match backend_type:
		NetworkEnums.BackendType.LAN:
			var lan_backend_script := load("res://addons/linkux/backends/lan/lan_backend.gd")
			_active_backend = lan_backend_script.new() as NetworkBackend
			_active_backend.name = "ActiveBackend"
			add_child(_active_backend)
			if _config and _config.lan:
				_active_backend._backend_initialize(_config.lan)

		NetworkEnums.BackendType.STEAM:
			var steam_backend_script := load("res://addons/linkux/backends/steam/steam_backend.gd")
			_active_backend = steam_backend_script.new() as NetworkBackend
			_active_backend.name = "ActiveBackend"
			add_child(_active_backend)
			if _config and _config.steam:
				_active_backend._backend_initialize(_config.steam)
			else:
				_active_backend._backend_initialize(null)

	if _active_backend and _transport_layer:
		var net_config: NetworkConfig = _config.network if _config else null
		_transport_layer.setup(_active_backend, _events, _logger, _debug_hooks, net_config)

	# Check capabilities
	if _active_backend:
		var check := BackendCapabilityChecker.check_required_capabilities(_active_backend)
		if not check["ok"]:
			_logger.warn("Backend missing capabilities: %s" % str(check["missing"]), "Core")

	if _session_manager:
		_session_manager.update_backend(_active_backend)

	if _backend_type == NetworkEnums.BackendType.LAN or _backend_type == NetworkEnums.BackendType.STEAM:
		_disable_scene_tree_multiplayer_poll_for_lan()

	_logger.info("Backend set: %s" % _get_backend_name(), "Core")


func get_config() -> LinkUxConfig:
	return _config


func get_protocol_version() -> int:
	return ProtocolVersion.get_version()


static func get_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load("res://addons/linkux/plugin.cfg") == OK:
		return cfg.get_value("plugin", "version", "unknown")
	return "unknown"


# ══════════════════════════════════════════════════════════════════════════════
# SESSION
# ══════════════════════════════════════════════════════════════════════════════

func prepare_for_new_session() -> void:
	## Unsticks JOINING/IN_SESSION in SessionManager when LinkUx is already READY (common source of error 114 on retry).
	## `initialize()` has not run yet: do not force `close_session` (INIT→DISCONNECTING is invalid and only clutters the log).
	if _state_machine.is_state(NetworkEnums.InternalState.INIT):
		return
	if not _state_machine.is_state(NetworkEnums.InternalState.READY):
		close_session()
		return
	_fix_session_manager_if_ready_but_busy()


func create_session(session_name: String, max_players: int = 16, metadata: Dictionary = {}) -> int:
	if _active_backend == null:
		return NetworkEnums.ErrorCode.BACKEND_NOT_SET
	prepare_for_new_session()
	## After `close_session`, `multiplayer_poll` is restored; when re-hosting LAN/Steam it must be disabled again or the engine treats LinkUx packets as scene RPCs.
	if _backend_type == NetworkEnums.BackendType.LAN or _backend_type == NetworkEnums.BackendType.STEAM:
		_disable_scene_tree_multiplayer_poll_for_lan()
	if _state_machine.is_state(NetworkEnums.InternalState.RUNNING) or _state_machine.is_state(NetworkEnums.InternalState.IN_SESSION) or _state_machine.is_state(NetworkEnums.InternalState.CONNECTING):
		return NetworkEnums.ErrorCode.ALREADY_IN_SESSION

	_state_machine.transition_to(NetworkEnums.InternalState.CONNECTING)
	var result: int = _session_manager.create_session(session_name, max_players, metadata)
	if result != NetworkEnums.ErrorCode.SUCCESS:
		if _state_machine.is_state(NetworkEnums.InternalState.CONNECTING):
			_state_machine.transition_to(NetworkEnums.InternalState.READY)
	return result


func join_session(session_info: SessionInfo) -> int:
	if _active_backend == null:
		return NetworkEnums.ErrorCode.BACKEND_NOT_SET
	prepare_for_new_session()
	## Same reason as `create_session`: `_init_linkux` does not call `set_backend` if the backend is unchanged, so the poll must be disabled again here.
	if _backend_type == NetworkEnums.BackendType.LAN or _backend_type == NetworkEnums.BackendType.STEAM:
		_disable_scene_tree_multiplayer_poll_for_lan()
	if _state_machine.is_state(NetworkEnums.InternalState.RUNNING) or _state_machine.is_state(NetworkEnums.InternalState.IN_SESSION) or _state_machine.is_state(NetworkEnums.InternalState.CONNECTING):
		return NetworkEnums.ErrorCode.ALREADY_IN_SESSION

	_state_machine.transition_to(NetworkEnums.InternalState.CONNECTING)
	var result: int = _session_manager.join_session(session_info)
	if result != NetworkEnums.ErrorCode.SUCCESS:
		if _state_machine.is_state(NetworkEnums.InternalState.CONNECTING):
			_state_machine.transition_to(NetworkEnums.InternalState.READY)
	return result


func join_session_by_room_code(room_code: String) -> int:
	if _active_backend == null:
		return NetworkEnums.ErrorCode.BACKEND_NOT_SET
	prepare_for_new_session()
	if _backend_type == NetworkEnums.BackendType.LAN or _backend_type == NetworkEnums.BackendType.STEAM:
		_disable_scene_tree_multiplayer_poll_for_lan()
	if _state_machine.is_state(NetworkEnums.InternalState.RUNNING) or _state_machine.is_state(NetworkEnums.InternalState.IN_SESSION) or _state_machine.is_state(NetworkEnums.InternalState.CONNECTING):
		return NetworkEnums.ErrorCode.ALREADY_IN_SESSION

	_state_machine.transition_to(NetworkEnums.InternalState.CONNECTING)
	var result: int = _session_manager.join_session_by_room_code(room_code)
	if result != NetworkEnums.ErrorCode.SUCCESS:
		if _state_machine.is_state(NetworkEnums.InternalState.CONNECTING):
			_state_machine.transition_to(NetworkEnums.InternalState.READY)
	return result


func close_session() -> void:
	## Close the backend without emitting `session_closed` until READY (SessionManager allows this with the flag).
	## Prevents the menu from reacting mid-shutdown while still RUNNING/IN_SESSION (avoids error 114 on retry).
	if _state_machine.is_state(NetworkEnums.InternalState.READY):
		_fix_session_manager_if_ready_but_busy()
		return

	if _state_machine.is_state(NetworkEnums.InternalState.CONNECTING):
		_session_manager.close_session(false)
		_cleanup_session()
		_state_machine.transition_to(NetworkEnums.InternalState.READY)
		_events.session_closed.emit()
		return

	if not _state_machine.transition_to(NetworkEnums.InternalState.DISCONNECTING):
		if not _state_machine.is_state(NetworkEnums.InternalState.DISCONNECTING):
			_state_machine.force_state(NetworkEnums.InternalState.DISCONNECTING)

	_session_manager.close_session(false)
	_cleanup_session()
	if not _state_machine.transition_to(NetworkEnums.InternalState.READY):
		_state_machine.force_state(NetworkEnums.InternalState.READY)
	_events.session_closed.emit()


func get_current_room_code() -> String:
	if _current_session == null:
		return ""
	return _current_session.room_code


func get_room_code() -> String:
	return get_current_room_code()


func has_room() -> bool:
	return get_room() != null


func _fix_session_manager_if_ready_but_busy() -> void:
	if _session_manager == null or not _session_manager.has_method("get_state"):
		return
	if int(_session_manager.get_state()) == int(SessionManager.SessionState.IDLE):
		return
	_session_manager.close_session(false)
	_cleanup_session()


func get_current_session() -> SessionInfo:
	return _current_session


func get_room() -> SessionInfo:
	return _current_session


func is_in_session() -> bool:
	return _state_machine.is_state(NetworkEnums.InternalState.IN_SESSION) or _state_machine.is_state(NetworkEnums.InternalState.RUNNING)


func is_client() -> bool:
	return is_in_session() and not is_host()


func is_singleplayer() -> bool:
	if not is_in_session():
		return true
	return get_players().size() <= 1


func is_multiplayer() -> bool:
	return is_in_session() and get_players().size() > 1


# ══════════════════════════════════════════════════════════════════════════════
# CONNECTION STATE
# ══════════════════════════════════════════════════════════════════════════════

func is_host() -> bool:
	if _active_backend:
		return _active_backend._backend_is_host()
	return false


func get_local_peer_id() -> int:
	if _active_backend:
		return _active_backend._backend_get_local_peer_id()
	return -1


func get_connected_peers() -> Array[int]:
	if _active_backend:
		return _active_backend._backend_get_connected_peers()
	return []


func kick_player(peer_id: int, reason: String = "") -> void:
	## Kicks a peer from the session. The kicked client receives the reason string as an error message.
	## Only valid when called from the host.
	if _active_backend:
		_active_backend._backend_kick_peer(peer_id, reason)


func get_player_info(peer_id: int) -> PlayerInfo:
	return _players.get(peer_id, null)


func get_players() -> Array[PlayerInfo]:
	var out: Array[PlayerInfo] = []
	for p: PlayerInfo in _players.values():
		out.append(p)
	return out


func get_client_players() -> Array[PlayerInfo]:
	var out: Array[PlayerInfo] = []
	for p: PlayerInfo in _players.values():
		if p and not p.is_host:
			out.append(p)
	return out


func get_host_player() -> PlayerInfo:
	for p: PlayerInfo in _players.values():
		if p and p.is_host:
			return p
	if _current_session:
		return get_player_info(_current_session.host_peer_id)
	return null


func get_local_player() -> PlayerInfo:
	return get_player_info(get_local_peer_id())



func is_local_player_id(peer_id: int) -> bool:
	if not LinkUx.is_in_session():
		return true
	if peer_id < 1:
		return false
	return peer_id == get_local_peer_id()


func is_local_player_info(player_info: PlayerInfo) -> bool:
	if player_info == null:
		return false
	return is_local_player_id(player_info.peer_id)


func get_remote_players() -> Array[PlayerInfo]:
	var local_peer_id := get_local_peer_id()
	var out: Array[PlayerInfo] = []
	for p: PlayerInfo in _players.values():
		if p and p.peer_id != local_peer_id:
			out.append(p)
	return out


func is_player_connected(peer_id: int) -> bool:
	return _players.has(peer_id)


func get_connection_state() -> int:
	return _state_machine.get_state()


func get_backend_type() -> int:
	return _backend_type


func get_backend_name() -> String:
	return _get_backend_name()


func is_lan() -> bool:
	return _backend_type == NetworkEnums.BackendType.LAN


func is_online() -> bool:
	return _backend_type == NetworkEnums.BackendType.STEAM


# ══════════════════════════════════════════════════════════════════════════════
# STEAM
# ══════════════════════════════════════════════════════════════════════════════

## Initializes the Steam API with the given AppID.
## Returns the Steam singleton object at runtime, or null if GodotSteam is not installed.
## Using Engine.get_singleton() avoids parser-time errors when GodotSteam is absent.
func _get_steam_singleton() -> Object:
	if ClassDB.class_exists("Steam"):
		return Engine.get_singleton("Steam")
	return null


## Writes steam_appid.txt next to the executable (or project root in editor) before calling
## steamInitEx so Steam's DLL picks up the AppID regardless of project settings.
## Returns true on success, false if GodotSteam is unavailable or Steam is not running.
func initialize_steam(app_id: int = 480) -> bool:
	if _steam_initialized:
		return true
	var steam := _get_steam_singleton()
	if steam == null:
		_logger.warn("Steam class not found — GodotSteam GDExtension may not be installed.", "Steam")
		return false
	_write_steam_appid_file(app_id)
	var result: Dictionary = steam.steamInitEx(false, app_id)
	# STEAM_API_INIT_RESULT_OK == 0 — compared by value to avoid a parser-time
	# reference to Steam.STEAM_API_INIT_RESULT_OK when GodotSteam is absent.
	if result.get("status", -1) == 0:
		_steam_initialized = true
		_logger.info("Steam initialized. User: %s (AppID: %d)" % [steam.getPersonaName(), app_id], "Steam")
		return true
	_logger.warn("Steam initialization failed: %s" % result.get("verbal", "unknown"), "Steam")
	return false


## Returns true if Steam was successfully initialized via initialize_steam().
func is_steam_initialized() -> bool:
	return _steam_initialized


## Returns the display name of the currently logged-in Steam user.
## Returns an empty string if Steam is not initialized or GodotSteam is unavailable.
func get_steam_user() -> String:
	if not _steam_initialized:
		return ""
	var steam := _get_steam_singleton()
	if steam == null:
		return ""
	return steam.getPersonaName()


# ══════════════════════════════════════════════════════════════════════════════
# AUTHORITY
# ══════════════════════════════════════════════════════════════════════════════

func set_entity_authority(entity: Node, peer_id: int) -> void:
	_authority_manager.set_authority(entity, peer_id)
	if entity and entity.is_inside_tree() and _state_replicator and _state_replicator.has_method("set_entity_authority"):
		_state_replicator.set_entity_authority(entity.get_path(), peer_id)


func get_entity_authority(entity: Node) -> int:
	return _authority_manager.get_authority(entity)


func is_entity_authority(entity: Node) -> bool:
	return _authority_manager.get_authority(entity) == get_local_peer_id()


func request_authority(entity: Node) -> void:
	_authority_manager.request_authority(entity, get_local_peer_id())


func transfer_authority(entity: Node, to_peer_id: int) -> void:
	_authority_manager.transfer_authority(entity, to_peer_id)


func validate_authority_change(entity: Node, peer_id: int) -> bool:
	return _authority_manager.validate_change(entity, peer_id)


# ══════════════════════════════════════════════════════════════════════════════
# STATE REPLICATION
# ══════════════════════════════════════════════════════════════════════════════

func allocate_entity_network_id() -> int:
	if _state_replicator and _state_replicator.has_method("allocate_entity_network_id"):
		return _state_replicator.allocate_entity_network_id()
	return -1


func register_entity(entity: Node, properties: Array[String], mode: int = NetworkEnums.ReplicationMode.ON_CHANGE, net_entity_id: int = -1) -> void:
	_state_replicator.register_entity(entity, properties, mode, net_entity_id)


func unregister_entity(entity: Node) -> void:
	if entity == null:
		return
	var p: NodePath = entity.get_path()
	_state_replicator.unregister_entity(entity)
	if _authority_manager and _authority_manager.has_method("unregister_entity_path"):
		_authority_manager.unregister_entity_path(p)


func set_global_state(key: String, value: Variant) -> void:
	_state_replicator.set_global_state(key, value)


func get_global_state(key: String, default: Variant = null) -> Variant:
	return _state_replicator.get_global_state(key, default)


# ══════════════════════════════════════════════════════════════════════════════
# SCENE SYNC
# ══════════════════════════════════════════════════════════════════════════════

func request_scene_load(scene_path: String) -> void:
	_scene_sync.request_scene_load(scene_path)


func report_scene_ready() -> void:
	_scene_sync.report_scene_ready()


func replay_late_join_spawns_now(peer_id: int) -> void:
	## Antes de scene_all_ready (spawn del nuevo peer): unicast de entidades ya existentes al joiner.
	if not is_host():
		return
	late_join_spawn_replay_needed.emit(peer_id)


func run_late_join_snapshot_only(peer_id: int) -> void:
	if _late_join_handler and _late_join_handler.has_method("send_world_snapshot"):
		_late_join_handler.send_world_snapshot(peer_id)


# ══════════════════════════════════════════════════════════════════════════════
# RPC
# ══════════════════════════════════════════════════════════════════════════════

func send_rpc(target_peer: int, method_name: String, args: Array = [], reliable: bool = true) -> void:
	_rpc_relay.send_rpc(target_peer, method_name, args, reliable)


func send_rpc_to_host(method_name: String, args: Array = [], reliable: bool = true) -> void:
	_rpc_relay.send_rpc(1, method_name, args, reliable)


func broadcast_rpc(method_name: String, args: Array = [], reliable: bool = true) -> void:
	_rpc_relay.send_rpc(0, method_name, args, reliable)


func send_to_all(method_name: String, payload: Variant = null, reliable: bool = true) -> void:
	broadcast_rpc(method_name, _payload_to_args(payload), reliable)


func send_to_host(method_name: String, payload: Variant = null, reliable: bool = true) -> void:
	send_rpc_to_host(method_name, _payload_to_args(payload), reliable)


func send_to_player(peer_id: int, method_name: String, payload: Variant = null, reliable: bool = true) -> void:
	send_rpc(peer_id, method_name, _payload_to_args(payload), reliable)


func send_to_clients(method_name: String, payload: Variant = null, reliable: bool = true) -> void:
	var args := _payload_to_args(payload)
	var host := get_host_player()
	for p: PlayerInfo in get_players():
		if host and p.peer_id == host.peer_id:
			continue
		send_rpc(p.peer_id, method_name, args, reliable)


func register_rpc(method_name: String, callable: Callable) -> void:
	if _rpc_relay and _rpc_relay.has_method("register_handler"):
		_rpc_relay.register_handler(method_name, callable)


func unregister_rpc(method_name: String) -> void:
	if _rpc_relay and _rpc_relay.has_method("unregister_handler"):
		_rpc_relay.unregister_handler(method_name)


# ══════════════════════════════════════════════════════════════════════════════
# OPTIMIZATION
# ══════════════════════════════════════════════════════════════════════════════

func set_interest_area(entity: Node, area: Variant) -> void:
	_interest_manager.set_interest_area(entity, area)


func get_network_stats() -> Dictionary:
	return _disconnect_handler.get_stats()


# ══════════════════════════════════════════════════════════════════════════════
# DEBUG
# ══════════════════════════════════════════════════════════════════════════════

func enable_debug_overlay(enabled: bool = true) -> void:
	_debug_hooks.enabled = enabled


func get_debug_metrics() -> Dictionary:
	return {
		"state": _state_machine.get_state_name(),
		"tick": _tick_manager.get_current_tick() if _tick_manager.has_method("get_current_tick") else 0,
		"peers": get_connected_peers().size(),
		"backend": _get_backend_name(),
	}


func set_feedback_log_capacity(max_entries: int) -> void:
	_feedback_log_max_entries = maxi(1, max_entries)
	if _feedback_logs.size() > _feedback_log_max_entries:
		var to_drop: int = _feedback_logs.size() - _feedback_log_max_entries
		_feedback_logs = _feedback_logs.slice(to_drop, _feedback_logs.size())


func get_feedback_logs(limit: int = 0, min_level: int = DebugLogger.LogLevel.NONE) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for entry: Dictionary in _feedback_logs:
		var lvl: int = int(entry.get("level", DebugLogger.LogLevel.NONE))
		if lvl >= min_level:
			filtered.append(entry)
	if limit > 0 and filtered.size() > limit:
		return filtered.slice(filtered.size() - limit, filtered.size())
	return filtered


func get_logs(limit: int = 0) -> Array[Dictionary]:
	return get_feedback_logs(limit)


func get_logs_type(level_name: String, limit: int = 0) -> Array[Dictionary]:
	var target := level_name.strip_edges().to_upper()
	var filtered: Array[Dictionary] = []
	for entry: Dictionary in _feedback_logs:
		if String(entry.get("level_name", "")).to_upper() == target:
			filtered.append(entry)
	if limit > 0 and filtered.size() > limit:
		return filtered.slice(filtered.size() - limit, filtered.size())
	return filtered


func debug_mode(enabled: bool = true) -> void:
	enable_debug_overlay(enabled)
	if enabled:
		_logger.set_log_level(DebugLogger.LogLevel.DEBUG)
	else:
		var fallback_level := DebugLogger.LogLevel.INFO
		if _config:
			fallback_level = _config.log_level
		_logger.set_log_level(fallback_level)


func set_player_profile(display_name: String = "", metadata: Dictionary = {}, data: Dictionary = {}) -> void:
	if display_name != "":
		_local_player_profile["display_name"] = display_name
	if not metadata.is_empty():
		_local_player_profile["metadata"] = metadata.duplicate(true)
	if not data.is_empty():
		_local_player_profile["data"] = data.duplicate(true)
	_apply_local_profile_if_registered()


func set_local_player_name(display_name: String) -> void:
	set_player_profile(display_name)


func get_local_player_name() -> String:
	var local_player := get_local_player()
	if local_player:
		return local_player.display_name
	return String(_local_player_profile.get("display_name", ""))


func update_local_player_data(key: String, value: Variant) -> void:
	var map: Dictionary = _local_player_profile.get("data", {})
	map[key] = value
	_local_player_profile["data"] = map
	_apply_local_profile_if_registered()


func remove_local_player_data(key: String) -> void:
	var map: Dictionary = _local_player_profile.get("data", {})
	map.erase(key)
	_local_player_profile["data"] = map
	_apply_local_profile_if_registered()


func get_player_data(peer_id: int) -> Dictionary:
	var p := get_player_info(peer_id)
	if p == null:
		return {}
	return p.data


func set_player_data(peer_id: int, key: String, value: Variant) -> bool:
	var p := get_player_info(peer_id)
	if p == null:
		return false
	p.data[key] = value
	player_updated.emit(p)
	return true


func remove_player_data(peer_id: int, key: String) -> bool:
	var p := get_player_info(peer_id)
	if p == null:
		return false
	p.data.erase(key)
	player_updated.emit(p)
	return true


func clear_feedback_logs() -> void:
	_feedback_logs.clear()


func dump_network_state() -> Dictionary:
	return {
		"state_machine": _state_machine.get_state_name(),
		"backend": _get_backend_name(),
		"is_host": is_host(),
		"local_peer_id": get_local_peer_id(),
		"connected_peers": get_connected_peers(),
		"players": _players.keys(),
		"session": _current_session.to_dict() if _current_session else {},
	}


# ══════════════════════════════════════════════════════════════════════════════
# INTERNAL
# ══════════════════════════════════════════════════════════════════════════════

func _on_network_tick(tick: int, delta: float) -> void:
	if not _state_machine.is_state(NetworkEnums.InternalState.RUNNING):
		return

	# 1. Process state replication
	_state_replicator.process_tick(tick, delta)

	# 2. Check heartbeats
	_disconnect_handler.process_tick(tick, delta)

	# 3. Flush outgoing packets
	_rpc_relay.flush()


func _cleanup_session() -> void:
	var had_session := _current_session != null or _players.size() > 0
	_restore_scene_tree_multiplayer_poll()
	_players.clear()
	_current_session = null
	_state_replicator.clear_all()
	_authority_manager.clear_all()
	_peer_identity_map.clear()
	_tick_manager.reset()
	if _disconnect_handler and _disconnect_handler.has_method("reset"):
		_disconnect_handler.reset()
	if _scene_sync and _scene_sync.has_method("reset_session_sync"):
		_scene_sync.reset_session_sync()
	if had_session:
		session_ended.emit()


func _write_steam_appid_file(app_id: int) -> void:
	var path: String
	if OS.has_feature("editor"):
		path = ProjectSettings.globalize_path("res://steam_appid.txt")
	else:
		path = OS.get_executable_path().get_base_dir().path_join("steam_appid.txt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(str(app_id))
		file.close()
		_logger.info("steam_appid.txt written to: %s" % path, "Steam")
	else:
		_logger.warn("Could not write steam_appid.txt to: %s (error %d)" % [path, FileAccess.get_open_error()], "Steam")


func _get_backend_name() -> String:
	match _backend_type:
		NetworkEnums.BackendType.NONE:  return "None"
		NetworkEnums.BackendType.LAN:   return "LAN"
		NetworkEnums.BackendType.STEAM: return "Steam"
		_: return "Unknown"


func _register_internal_rpc_handlers() -> void:
	if _rpc_relay == null or not _rpc_relay.has_method("register_handler") or _scene_sync == null:
		return
	_rpc_relay.register_handler(
		"linkux_request_scene_load",
		Callable(_scene_sync, "_rpc_host_send_scene_load_to_peer")
	)
	_rpc_relay.register_handler("linkux_player_name", _on_rpc_player_name)


func _on_session_created(info: SessionInfo) -> void:
	_current_session = info
	_state_machine.transition_to(NetworkEnums.InternalState.IN_SESSION)
	_state_machine.transition_to(NetworkEnums.InternalState.RUNNING)
	_tick_manager.start()
	session_started.emit()


func _on_session_joined(info: SessionInfo) -> void:
	_current_session = info
	_state_machine.transition_to(NetworkEnums.InternalState.IN_SESSION)
	session_started.emit()
	# Transmit local player name to host; flush immediately since the tick loop hasn't started yet.
	var local_name := String(_local_player_profile.get("display_name", ""))
	if not local_name.is_empty():
		_rpc_relay.send_rpc(1, "linkux_player_name", [local_name], true)
		_rpc_relay.flush()


func _on_scene_all_ready(_path: String) -> void:
	if _state_machine.is_state(NetworkEnums.InternalState.IN_SESSION):
		_state_machine.transition_to(NetworkEnums.InternalState.RUNNING)
		_tick_manager.start()


func _on_player_joined(info: PlayerInfo) -> void:
	_players[info.peer_id] = info
	if info.peer_id == get_local_peer_id():
		_apply_local_profile_if_registered()


func _on_player_left(peer_id: int, _reason: int) -> void:
	var left_player: PlayerInfo = _players.get(peer_id, null)
	_players.erase(peer_id)
	_authority_manager.on_peer_disconnected(peer_id)
	if left_player:
		player_left_processed.emit(left_player, _reason)


func _on_connection_failed_reset_state(_err: String) -> void:
	## create/join dejan LinkUx en CONNECTING; si el backend emite fallo, volver a READY o no se puede reintentar host.
	if _state_machine.is_state(NetworkEnums.InternalState.CONNECTING):
		_state_machine.transition_to(NetworkEnums.InternalState.READY)
	elif _state_machine.is_state(NetworkEnums.InternalState.IN_SESSION) or _state_machine.is_state(NetworkEnums.InternalState.RUNNING):
		_tick_manager.stop()
		_cleanup_session()
		_state_machine.transition_to(NetworkEnums.InternalState.READY)


func _on_logger_log_emitted(level: int, level_name: String, context: String, message: String, formatted: String, timestamp_msec: int) -> void:
	var entry: Dictionary = {
		"level": level,
		"level_name": level_name,
		"context": context,
		"message": message,
		"formatted": formatted,
		"timestamp_msec": timestamp_msec,
	}
	_feedback_logs.append(entry)
	if _feedback_logs.size() > _feedback_log_max_entries:
		_feedback_logs.remove_at(0)
	feedback_log_added.emit(entry)


func _disable_scene_tree_multiplayer_poll_for_lan() -> void:
	var tree := get_tree()
	if tree == null or _scene_tree_multiplayer_poll_overridden:
		return
	_scene_tree_multiplayer_poll_saved = tree.multiplayer_poll
	tree.multiplayer_poll = false
	_scene_tree_multiplayer_poll_overridden = true


func _restore_scene_tree_multiplayer_poll() -> void:
	var tree := get_tree()
	if tree == null or not _scene_tree_multiplayer_poll_overridden:
		return
	tree.multiplayer_poll = _scene_tree_multiplayer_poll_saved
	_scene_tree_multiplayer_poll_overridden = false


func _process(_delta: float) -> void:
	if _transport_layer:
		_transport_layer.poll()


func _payload_to_args(payload: Variant) -> Array:
	if payload == null:
		return []
	if payload is Array:
		return payload
	return [payload]


func _on_rpc_player_name(from_peer: int, name: String) -> void:
	_session_manager.register_player_name(from_peer, name)
	# Host responds with its own name so the client can resolve its pending host entry.
	if is_host():
		var local_name := String(_local_player_profile.get("display_name", ""))
		if not local_name.is_empty():
			_rpc_relay.send_rpc(from_peer, "linkux_player_name", [local_name], true)
			_rpc_relay.flush()


func _apply_local_profile_if_registered() -> void:
	var local_player := get_local_player()
	if local_player == null:
		return
	local_player.display_name = String(_local_player_profile.get("display_name", local_player.display_name))
	local_player.metadata = Dictionary(_local_player_profile.get("metadata", {})).duplicate(true)
	local_player.data = Dictionary(_local_player_profile.get("data", {})).duplicate(true)
	player_updated.emit(local_player)
