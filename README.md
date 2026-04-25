# LinkUx

[![Godot 4](https://img.shields.io/badge/Godot-4.2+-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org/)
[![Version](https://img.shields.io/badge/version-2.0.0-8435c4)](./plugin.cfg)

**LinkUx** is a **multiplayer abstraction addon** for [**Godot 4**](https://godotengine.org/). It exposes one high-level **Autoload API** (`LinkUx`) while routing traffic through **pluggable backends**—today **LAN (ENet)** with a clean path for **online** transports later—so gameplay code stays the same whether players join over the local network or the internet.

Sessions, players, scene readiness, authority, state replication, RPC routing, late join, and tick helpers are coordinated internally. You configure the active backend, call `create_session` / `join_session` / `close_session`, react to signals, and attach optional nodes such as **`LinkUxEntity`**, **`LinkUxSynchronizer`**, and **`LinkUxSpawner`** where you need replicated entities and properties.

---

## 📑 Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Documentation](#documentation)
- [Project layout](#project-layout)
- [Credits](#credits)

---

## ✨ Features

| | |
| :--- | :--- |
| **Single public API** | One **`LinkUx`** Autoload: sessions, signals, helpers, and typed message routing. |
| **Swappable backends** | **`NetworkBackend`** contract; **LAN** backend included (binary protocol on top of ENet). Online-oriented backends can be added without rewriting game flow. |
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
| **Godot 4.2+** | Yes | Developed and tested on Godot **4.x** (see [`plugin.cfg`](./plugin.cfg)). |
| **Same addon version** | Yes | All players must share a **compatible** [`protocol_version.gd`](./core/protocol_version.gd) build or joins may fail with `PROTOCOL_VERSION_MISMATCH`. |

Expected install path in your project:

```text
res://addons/linkux/
```

---

## 📦 Installation

1. Copy this repository’s `addons/linkux` folder into your Godot project under **`res://addons/linkux/`**.
2. Open **Project → Project Settings → Plugins**.
3. Enable **LinkUx** — the editor registers the **`LinkUx`** autoload (see [`plugin.gd`](./plugin.gd) and [`linkux.tscn`](./linkux.tscn)).
4. Configure your default backend / resources (for example **`LinkUxConfig`** and **`LanBackendConfig`**) as described in the docs.
5. From gameplay / UI code, call **`LinkUx.create_session(...)`**, **`LinkUx.join_session(...)`**, etc.

---

## 🚀 Quick start

### 1️⃣ Verify the autoload

After enabling the plugin, you should see **`LinkUx`** under **Project → Project Settings → Autoloads**, pointing at `res://addons/linkux/linkux.tscn`.

### 2️⃣ Host or join from code

```gdscript
func _on_host_pressed() -> void:
    var err := LinkUx.create_session("My Lobby", 8, {})
    if err != NetworkEnums.ErrorCode.SUCCESS:
        push_error("create_session failed: %s" % err)


func _on_join_pressed(info: SessionInfo) -> void:
    var err := LinkUx.join_session(info)
    if err != NetworkEnums.ErrorCode.SUCCESS:
        push_error("join_session failed: %s" % err)
```

### 3️⃣ React to session signals

```gdscript
func _ready() -> void:
    LinkUx.session_created.connect(_on_session_created)
    LinkUx.player_joined.connect(_on_player_joined)


func _on_session_created(_info: SessionInfo) -> void:
    print("Session ready")


func _on_player_joined(_player: PlayerInfo) -> void:
    print("Peer joined")
```

### 4️⃣ Replicate entities

- Add **`LinkUxEntity`** (or compatible setup) to scenes you spawn through **`LinkUxSpawner`**.
- Attach **`LinkUxSynchronizer`** to nodes whose properties should follow network state; use the inspector’s **Synchronized Properties** section to pick fields.

*(Exact API names and enums live on the `LinkUx` facade and the global `NetworkEnums` class—use your IDE’s go-to-definition on the autoload.)*

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
├── backends/               # Backends implementation
├── subsystems/             # Session, replication, RPC relay, scene sync, ticks, etc.
├── transport/              # Transport layer, channels, validation
├── nodes/                  # LinkUxEntity, Spawner, Synchronizer + editor tools
├── debug/                  # Logger, debugger hooks, stats helpers
├── optimization/           # Interest management, batching, interpolation helpers
└── security/               # Authority / error helpers
```

---

## 🙏 Credits

- **LinkUx** — **IUX Games**, **Isaackiux** · version **2.0.0** (see [`plugin.cfg`](./plugin.cfg)).
