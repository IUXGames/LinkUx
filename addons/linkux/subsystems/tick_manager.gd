class_name TickManager
extends Node
## Fixed-rate network tick loop decoupled from frame rate.
## Uses _physics_process with an accumulator for deterministic timing.

signal network_tick(tick_number: int, delta: float)

var _tick_rate: int = 20
var _tick_interval: float = 0.05
var _accumulator: float = 0.0
var _current_tick: int = 0
var _running: bool = false
var _logger: DebugLogger
var _events: NetworkEvents
var _debug_hooks: DebugHooks


func setup(config: NetworkConfig, events: NetworkEvents, logger: DebugLogger, debug_hooks: DebugHooks) -> void:
	_events = events
	_logger = logger
	_debug_hooks = debug_hooks
	if config:
		_tick_rate = config.tick_rate
		_tick_interval = 1.0 / float(_tick_rate)
	_logger.debug("TickManager configured: %d Hz (%.3fs interval)" % [_tick_rate, _tick_interval], "TickManager")


func start() -> void:
	_running = true
	_accumulator = 0.0
	_logger.info("Tick loop started at %d Hz" % _tick_rate, "TickManager")


func stop() -> void:
	_running = false
	_logger.info("Tick loop stopped", "TickManager")


func reset() -> void:
	_running = false
	_accumulator = 0.0
	_current_tick = 0


func get_current_tick() -> int:
	return _current_tick


func get_tick_rate() -> int:
	return _tick_rate


func get_tick_interval() -> float:
	return _tick_interval


func is_running() -> bool:
	return _running


func _physics_process(delta: float) -> void:
	if not _running:
		return

	_accumulator += delta

	while _accumulator >= _tick_interval:
		_accumulator -= _tick_interval
		_current_tick += 1
		network_tick.emit(_current_tick, _tick_interval)

		if _events:
			_events.network_tick.emit(_current_tick, _tick_interval)
