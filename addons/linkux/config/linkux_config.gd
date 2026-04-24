class_name LinkUxConfig
extends Resource
## Top-level configuration resource for LinkUx.
## Create a .tres file with this resource and pass it to LinkUx.initialize().

@export var default_backend: NetworkEnums.BackendType = NetworkEnums.BackendType.NONE
@export var network: NetworkConfig
@export var lan: LanBackendConfig
# Add config fields for new backends here (e.g. @export var eos: EosBackendConfig)
@export var advanced: AdvancedConfig
@export var debug_enabled: bool = false
@export var log_level: int = 3 ## 0=none, 1=error, 2=warn, 3=info, 4=debug, 5=trace
