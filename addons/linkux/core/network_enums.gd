class_name NetworkEnums
extends RefCounted
## Centralized enumerations for the entire LinkUx system.


enum BackendType {
	NONE = -1, ## No backend selected; set one explicitly before creating/joining a session.
	LAN  =  0,
	# Add new online backends here (e.g. EOS, Relay, etc.)
}

enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	IN_SESSION,
	DISCONNECTING,
	ERROR,
	IDLE,
}

enum InternalState {
	INIT,
	READY,
	CONNECTING,
	IN_SESSION,
	RUNNING,
	DISCONNECTING,
	ERROR,
}

enum AuthorityMode {
	HOST,         ## Host controls this entity (server-authoritative).
	OWNER,        ## The peer who spawned it controls it (client-authoritative).
	TRANSFERABLE, ## Authority can be dynamically transferred between peers.
}

enum ReplicationMode {
	ALWAYS,    ## Send every tick regardless of change.
	ON_CHANGE, ## Send only when value differs from last sent.
	MANUAL,    ## Only send when explicitly triggered.
}

enum DisconnectReason {
	GRACEFUL,
	TIMEOUT,
	KICKED,
	HOST_CLOSED,
	ERROR,
}

enum ChannelType {
	RPC = 0,
	STATE = 1,
	CONTROL = 2,
}

enum MessageType {
	# State
	STATE_FULL = 0x01,
	STATE_DELTA = 0x02,
	GLOBAL_STATE_UPDATE = 0x03,
	GLOBAL_STATE_REQUEST = 0x04,

	# RPC
	RPC_RELIABLE = 0x10,
	RPC_UNRELIABLE = 0x11,

	# Authority
	AUTH_REQUEST = 0x20,
	AUTH_TRANSFER_BEGIN = 0x21,
	AUTH_TRANSFER_ACK = 0x22,
	AUTH_CHANGED = 0x23,
	AUTH_LOCKED = 0x24,
	AUTH_DENIED = 0x25,

	# Scene Sync
	SCENE_LOAD_REQUEST = 0x30,
	SCENE_READY_REPORT = 0x31,
	SCENE_ALL_READY = 0x32,

	# Late Join
	WORLD_SNAPSHOT = 0x40,
	WORLD_SNAPSHOT_CHUNK = 0x41,
	WORLD_SNAPSHOT_ACK = 0x42,

	# Connection
	HEARTBEAT = 0x50,
	HEARTBEAT_ACK = 0x51,
	DISCONNECT_NOTICE = 0x52,
	PROTOCOL_HANDSHAKE = 0x53,

	# Entity Registration
	ENTITY_REGISTER = 0x60,
	ENTITY_UNREGISTER = 0x61,
	ENTITY_PATH_MAP = 0x62,
	ENTITY_SPAWNED = 0x63,
	ENTITY_DESPAWNED = 0x64,
}

enum ErrorCode {
	SUCCESS = 0,
	NETWORK_UNAVAILABLE = 101,
	SESSION_NOT_FOUND = 102,
	SESSION_FULL = 103,
	AUTHORITY_DENIED = 104,
	AUTHORITY_TRANSFER_FAILED = 105,
	PROTOCOL_VERSION_MISMATCH = 106,
	BACKEND_INCOMPATIBLE = 107,
	SERIALIZATION_FAILED = 108,
	PACKET_VALIDATION_FAILED = 109,
	RATE_LIMIT_EXCEEDED = 110,
	HEARTBEAT_TIMEOUT = 111,
	INVALID_STATE_TRANSITION = 112,
	BACKEND_NOT_SET = 113,
	ALREADY_IN_SESSION = 114,
	NOT_HOST = 115,
	ENTITY_NOT_REGISTERED = 116,
}
