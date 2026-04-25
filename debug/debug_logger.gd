class_name DebugLogger
extends RefCounted
## Centralized logging for the LinkUx addon with configurable log levels.

signal log_emitted(level: int, level_name: String, context: String, message: String, formatted: String, timestamp_msec: int)

enum LogLevel {
	NONE = 0,
	ERROR = 1,
	WARN = 2,
	INFO = 3,
	DEBUG = 4,
	TRACE = 5,
}

var log_level: int = LogLevel.INFO
var _prefix := "[LinkUx] "


func set_log_level(level: int) -> void:
	log_level = level


func error(message: String, context: String = "") -> void:
	if log_level >= LogLevel.ERROR:
		var msg := _format_message("ERROR", message, context)
		push_error(msg)
		_emit_log(LogLevel.ERROR, "ERROR", context, message, msg)


func warn(message: String, context: String = "") -> void:
	if log_level >= LogLevel.WARN:
		var msg := _format_message("WARN", message, context)
		push_warning(msg)
		_emit_log(LogLevel.WARN, "WARN", context, message, msg)


func info(message: String, context: String = "") -> void:
	if log_level >= LogLevel.INFO:
		var msg := _format_message("INFO", message, context)
		print(msg)
		_emit_log(LogLevel.INFO, "INFO", context, message, msg)


func debug(message: String, context: String = "") -> void:
	if log_level >= LogLevel.DEBUG:
		var msg := _format_message("DEBUG", message, context)
		print(msg)
		_emit_log(LogLevel.DEBUG, "DEBUG", context, message, msg)


func trace(message: String, context: String = "") -> void:
	if log_level >= LogLevel.TRACE:
		var msg := _format_message("TRACE", message, context)
		print(msg)
		_emit_log(LogLevel.TRACE, "TRACE", context, message, msg)


func _format_message(level_name: String, message: String, context: String) -> String:
	var msg := _prefix + level_name
	if context != "":
		msg += " [%s]" % context
	msg += ": " + message
	return msg


func _emit_log(level: int, level_name: String, context: String, message: String, formatted: String) -> void:
	log_emitted.emit(level, level_name, context, message, formatted, Time.get_ticks_msec())
