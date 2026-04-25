class_name LanBackendConfig
extends Resource
## LAN backend specific configuration.

@export var default_port: int = 7777
@export var max_clients: int = 16
## Multiple hosts/games on one machine: try default_port, default_port+stride, …
@export var lan_port_stride: int = 2
## How many game port slots to try.
@export var max_lan_host_attempts: int = 8
@export var in_bandwidth: int = 0  ## 0 = unlimited
@export var out_bandwidth: int = 0 ## 0 = unlimited
## Maximum time (seconds) for the **client** ENet connection to complete after `create_client`.
## On timeout the attempt is closed and `connection_failed` is emitted (useful for fast feedback when joining from code).
@export var connection_timeout: float = 3.0
