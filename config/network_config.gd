class_name NetworkConfig
extends Resource
## Network timing and optimization configuration.

@export_range(1, 128) var tick_rate: int = 20
@export var interpolation_delay_ms: float = 100.0
@export var extrapolation_limit_ms: float = 250.0
@export_range(5, 120) var max_snapshot_buffer_size: int = 30
@export var heartbeat_interval_ms: float = 5000.0
@export var disconnect_timeout_ms: float = 15000.0
@export var packet_batch_enabled: bool = true
@export var delta_compression_enabled: bool = true
@export var max_packet_size: int = 4096
@export_range(1, 100) var max_rpc_per_tick: int = 10
