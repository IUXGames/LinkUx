class_name SteamBackendConfig
extends Resource
## Steam backend specific configuration.

## Maximum time (seconds) for the client Steam connection to complete after joining a lobby.
@export var connection_timeout: float = 10.0
## Steam lobby type: 0=Private, 1=FriendsOnly, 2=Public, 3=Invisible.
@export var lobby_type: int = 2
