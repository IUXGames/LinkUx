# LinkUx

[![Godot 4](https://img.shields.io/badge/Godot-4.4+-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org/)
[![Version](https://img.shields.io/badge/version-2.1.1-8435c4)](./plugin.cfg)

**LinkUx** is a **multiplayer abstraction addon** for [**Godot 4**](https://godotengine.org/). It exposes one high-level **Autoload API** (`LinkUx`) while routing traffic through **pluggable backends**—**LAN (ENet)** and **Online (Steam)**—so gameplay code stays the same whether players join over the local network or the internet.

Sessions, players, scene readiness, authority, state replication, RPC routing, late join, and tick helpers are coordinated internally. You configure the active backend, call `create_session` / `join_session` / `close_session`, react to signals, and attach optional nodes such as **`LinkUxEntity`**, **`LinkUxSynchronizer`**, and **`LinkUxSpawner`** where you need replicated entities and properties.

---

## 📑 Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Documentation](#documentation)
- [Project layout](#project-layout)
- [Changelog](#changelog)
- [Credits](#credits)

---

## ✨ Features

| | |
| :--- | :--- |
| **Single public API** | One **`LinkUx`** Autoload: sessions, signals, helpers, and typed message routing. |
| **Swappable backends** | **`NetworkBackend`** contract; **LAN** and **Steam** backends included. New transports can be added without rewriting game flow. |
| **Steam Online backend** | Full online multiplayer via **Steam Lobbies** + **SteamMultiplayerPeer**. Room-code discovery (6-char alphanumeric), relay & encryption handled by Steam. |
| **Listen-server friendly** | Peer-to-host style session and authority model aligned with typical co-op / small competitive games. |
| **State replication** | **`StateReplicator`** + **`LinkUxSynchronizer`** for snapshots / deltas and optional interpolation. |
| **Scene sync** | Host-driven scene load / ready gates so all peers transition together. |
| **Spawning** | **`LinkUxSpawner`** for replicated spawn and teardown of entity scenes. |
| **RPC & messages** | **`MessageRegistry`** with serialization helpers and **`RpcRelay`** for routing where the transport requires it. |
| **Debug & tooling** | Debug logger, hooks, network stats helpers, and an **inspector plugin** for configuring **`sync_properties`** on synchronizers. |
| **Editor integration** | Plugin registers the **`LinkUx`** autoload on enable; custom node types with icons. |

---

## 📋 Requirements

| Item | Required? | Notes |
| :--- | :---: | :--- |
| **Godot 4.4+** | Yes | Developed and tested on Godot **4.4+** (see [`plugin.cfg`](./plugin.cfg)). |
| **Same addon version** | Yes | All players must share a **compatible** [`protocol_version.gd`](./core/protocol_version.gd) build or joins may fail with `PROTOCOL_VERSION_MISMATCH`. |
| **GodotSteam GDExtension 4.4+** | Steam backend only | Official [**GodotSteam**](https://godotsteam.com/) plugin by **Gramps**. Required only when using `NetworkEnums.BackendType.STEAM`. |

Expected install path in your project:

```text
res://addons/linkux/
```

---

## 📦 Installation

1. Copy this repository's `addons/linkux` folder into your Godot project under **`res://addons/linkux/`**.
2. Open **Project → Project Settings → Plugins**.
3. Enable **LinkUx** — the editor registers the **`LinkUx`** autoload (see [`plugin.gd`](./plugin.gd) and [`linkux.tscn`](./linkux.tscn)).
4. Configure your default backend / resources (for example **`LinkUxConfig`** and **`LanBackendConfig`**) as described in the docs.
5. From gameplay / UI code, call **`LinkUx.create_session(...)`**, **`LinkUx.join_session(...)`**, etc.

> **Steam backend:** also install [GodotSteam GDExtension 4.4+](https://godotsteam.com/) and call `LinkUx.initialize_steam(your_app_id)` before switching to the Steam backend.

---

## 🚀 Quick start

### 1️⃣ Verify the autoload

After enabling the plugin, you should see **`LinkUx`** under **Project → Project Settings → Autoloads**, pointing at `res://addons/linkux/linkux.tscn`.

### 2️⃣ Host or join (LAN)

```gdscript
func _on_host_pressed() -> void:
    LinkUx.set_backend(NetworkEnums.BackendType.LAN)
    var err := LinkUx.create_session("My Lobby", 8, {})
    if err != NetworkEnums.ErrorCode.SUCCESS:
        push_error("create_session failed: %s" % err)


func _on_join_pressed(info: SessionInfo) -> void:
    LinkUx.set_backend(NetworkEnums.BackendType.LAN)
    var err := LinkUx.join_session(info)
    if err != NetworkEnums.ErrorCode.SUCCESS:
        push_error("join_session failed: %s" % err)
```

### 3️⃣ Host or join (Steam Online)

```gdscript
func _ready() -> void:
    LinkUx.initialize_steam(480)  # use your real Steam App ID


func _on_online_host_pressed() -> void:
    LinkUx.set_backend(NetworkEnums.BackendType.STEAM)
    LinkUx.create_session("My Lobby", 8, {})
    # Listen to LinkUx.session_created to get the room code


func _on_online_join_pressed(room_code: String) -> void:
    LinkUx.set_backend(NetworkEnums.BackendType.STEAM)
    LinkUx.join_session_by_room_code(room_code)
```

### 4️⃣ React to session signals

```gdscript
func _ready() -> void:
    LinkUx.session_created.connect(_on_session_created)
    LinkUx.player_joined.connect(_on_player_joined)


func _on_session_created(info: SessionInfo) -> void:
    print("Session ready — room code: ", info.room_code)


func _on_player_joined(_player: PlayerInfo) -> void:
    print("Peer joined")
```

### 5️⃣ Replicate entities

- Add **`LinkUxEntity`** (or compatible setup) to scenes you spawn through **`LinkUxSpawner`**.
- Attach **`LinkUxSynchronizer`** to nodes whose properties should follow network state; use the inspector's **Synchronized Properties** section to pick fields.

*(Exact API names and enums live on the `LinkUx` facade and the global `NetworkEnums` class—use your IDE's go-to-definition on the autoload.)*

---

## 📚 Documentation

The **official documentation** is a website:

Then open **[LinkUx Official Documentation](https://iuxgames.github.io/LinkUx_WebSite/)** in your browser for the full interactive docs (navigation, **EN / ES** language toggle, and **quick search**).

---

## 🗂 Project layout

```text
addons/linkux/
├── plugin.cfg              # Plugin metadata
├── plugin.gd               # EditorPlugin: autoload + inspector registration
├── linkux.tscn             # Autoload scene root
├── linkux.gd               # LinkUx singleton (public API facade)
├── config/                 # LinkUxConfig, network & backend resources
├── core/                   # Enums, events, session/player info, protocol version, backends base
├── backends/
│   ├── lan/                # LAN backend (ENet)
│   └── steam/              # Steam Online backend (GodotSteam)
├── subsystems/             # Session, replication, RPC relay, scene sync, ticks, etc.
├── transport/              # Transport layer, channels, validation
├── nodes/                  # LinkUxEntity, Spawner, Synchronizer + editor tools
├── debug/                  # Logger, debugger hooks, stats helpers
├── optimization/           # Interest management, batching, interpolation helpers
└── security/               # Authority / error helpers
```

---

## 📝 Changelog

### v2.1.1
- **Fix: parse errors on projects without GodotSteam installed** — `linkux.gd` and `steam_backend.gd` previously referenced the `Steam` identifier and the `SteamMultiplayerPeer` type directly, causing GDScript parse errors at addon activation time when GodotSteam GDExtension was not present. All Steam API calls are now resolved at runtime:
  - `Steam.xxx()` calls replaced with a cached `Object` reference obtained via `Engine.get_singleton("Steam")`.
  - `Steam.STEAM_API_INIT_RESULT_OK` constant replaced with its numeric value (`0`) to avoid a parse-time class member lookup.
  - `var _peer: SteamMultiplayerPeer` type annotation changed to `var _peer: MultiplayerPeer` (base class, always available).
  - `SteamMultiplayerPeer.new()` replaced with `ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer`.
- **Behavior unchanged** — if GodotSteam is installed the Steam backend works exactly as before. If it is not installed, `set_backend(STEAM)` returns `ERR_UNAVAILABLE` and a warning is pushed; the LAN backend is unaffected.

### v2.1.0
- **New backend: Steam Online** (`NetworkEnums.BackendType.STEAM`) — full online multiplayer via Steam Lobbies and `SteamMultiplayerPeer`. Requires [GodotSteam GDExtension 4.4+](https://godotsteam.com/) by Gramps.
- **Room codes for online** — 6-character alphanumeric codes (A–Z, 0–9) backed by Steam Lobby metadata for session discovery.
- **New API functions:**
  - `LinkUx.initialize_steam(app_id)` — initializes GodotSteam, writes `steam_appid.txt` for editor and export environments automatically.
  - `LinkUx.is_steam_initialized()` — returns whether Steam was successfully initialized.
  - `LinkUx.get_steam_user()` — returns the local Steam display name, or `"Player"` if unavailable.
  - `LinkUx.get_version()` — returns the addon semantic version string from `plugin.cfg`.
- **`is_online()`** now returns `true` when the active backend is Steam.
- **Dynamic addon version** in handshake payload — `protocol_version.gd` now reads the version string from `plugin.cfg` instead of a hardcoded value.
- **Godot compatibility updated** to **4.4+**.

### v2.0.0
- Initial public release with LAN backend (ENet), full session/player lifecycle, state replication, RPC relay, scene sync, spawning, and editor tooling.

---

## 🙏 Credits

- **LinkUx** — **IUX Games**, **Isaackiux** · version **2.1.1** (see [`plugin.cfg`](./plugin.cfg)).
- **GodotSteam** — [Gramps](https://godotsteam.com/) · used as the transport layer for the Steam Online backend.
