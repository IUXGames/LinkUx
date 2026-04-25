class_name AdvancedConfig
extends Resource
## Advanced configuration with per-backend overrides and global options.

@export var enable_host_migration: bool = false
@export var max_reconnect_attempts: int = 3
@export var reconnect_timeout_ms: float = 10000.0
@export var ghost_player_timeout_ms: float = 30000.0
@export var max_bandwidth_per_second: int = 1024000 ## bytes
@export var max_state_updates_per_entity_per_tick: int = 1
