<!-- doc-shell:page slug="introduccion" -->

# Introducción

[![Godot 4](https://img.shields.io/badge/Godot-4.X-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org/)
[![Version](https://img.shields.io/badge/version-2.0.0-5aafff)](./plugin.cfg)

**LinkUx** es un addon de multijugador para **Godot 4** que unifica redes LAN y Online bajo una única API de alto nivel. En lugar de programar directamente contra ENet, WebSocket o cualquier servicio externo, tu código de juego solo habla con LinkUx — y LinkUx se encarga del resto.

## Versiones y compatibilidad

| Información | Valor |
|-------------|--------|
| **Versión del addon** | **2.0.0** (campo `version` en `addons/linkux/plugin.cfg`) |
| **Godot para el que está diseñado** | **Godot 4.x** (desarrollo y pruebas a partir de **Godot 4.2**) |
| **Protocolo de red interno** | Número entero expuesto por `LinkUx.get_protocol_version()` (ver `addons/linkux/core/protocol_version.gd`) |

**Importante:** todos los jugadores deben usar la **misma versión del addon** en sus proyectos. Si un cliente tiene otra versión incompatible del protocolo, la conexión puede fallar con `PROTOCOL_VERSION_MISMATCH` (`NetworkEnums.ErrorCode`).

## Filosofía

> Una sola API pública. Múltiples backends intercambiables.

El principio central de LinkUx es la **abstracción total del transporte**. Puedes cambiar de LAN a un backend Online sin tocar ni una línea de código de juego — solo cambias la configuración del backend.

## Arquitectura en capas

```
┌──────────────────────────────────────┐
│         Tu código de juego           │  ← Solo interactúa aquí
├──────────────────────────────────────┤
│         LinkUx — API pública         │  linkux.gd (Autoload)
├──────────────────────────────────────┤
│         Subsistemas internos         │  SessionManager, StateReplicator,
│                                      │  RpcRelay, SceneSync, etc.
├──────────────────────────────────────┤
│         Capa de transporte           │  TransportLayer
├──────────────────────────────────────┤
│         Backend activo               │  LAN (ENet) / Online (próximamente)
└──────────────────────────────────────┘
```

## Backends disponibles

| Backend | Estado | Descripción |
|---------|--------|-------------|
| **LAN** | ✅ Disponible | Red local usando ENet (ENetMultiplayerPeer) |
| **Online** | 🔜 Próximamente | Relay, servicios en la nube, matchmaking global |

## Características principales

- **API unificada** — `create_session`, `join_session`, `close_session`, señales, RPCs: todo en el mismo Autoload.
- **Nodos de editor** — `LinkUxEntity`, `LinkUxSynchronizer` y `LinkUxSpawner` se configuran visualmente en el inspector.
- **Sincronización con interpolación** — Suavizado automático de posición/rotación para objetos remotos.
- **Spawning replicado** — El Spawner crea y destruye entidades en todos los peers de forma automática.
- **Late join** — Los jugadores que se unen tarde reciben el estado actual del mundo automáticamente.
- **Autoridad de entidades** — Modelo flexible: HOST, OWNER o TRANSFERABLE.
- **RPCs tipados** — Sistema de mensajes registrados con validación y routing automático.
- **Debug integrado** — Feed de logs, métricas de red y volcado de estado en tiempo de ejecución.

## Requisitos

- **Godot 4.2 o superior** (recomendado mantenerse en la misma versión menor que la de desarrollo del addon)
- Sin dependencias externas en tiempo de ejecución

---

<!-- doc-shell:page slug="instalacion" -->

# Instalación

## Paso 1 — Copiar el addon

Copia la carpeta `addons/linkux/` dentro de tu proyecto Godot:

```
tu-proyecto/
└── addons/
    └── linkux/       ← pega aquí la carpeta completa
        ├── linkux.gd
        ├── plugin.gd
        ├── core/
        ├── backends/
        └── ...
```

## Paso 2 — Activar el plugin

Ve a **Project → Project Settings → Plugins** y activa **LinkUx**:

```
[ LinkUx ]  [ enable ]
```

Al activarlo, el plugin:
1. Registra los nodos `LinkUxEntity`, `LinkUxSynchronizer` y `LinkUxSpawner` en el editor.
2. Añade el autoload **`LinkUx`** a la escena raíz (disponible globalmente como `LinkUx`).

## Paso 3 — Verificar el autoload

En **Project → Project Settings → Autoloads** deberías ver:

```
LinkUx   res://addons/linkux/linkux.tscn   ✓
```

> El autoload se registra automáticamente al activar el plugin. No necesitas añadirlo manualmente.

## Paso 4 — Inicializar en tu juego

LinkUx **no se configura automáticamente**. Debes llamar a `LinkUx.initialize()` una vez al arrancar tu juego (normalmente en un Autoload propio):

```gdscript
# GLOBAL.gd — Tu autoload de juego
extends Node

func _ready() -> void:
    # Esperar un frame para que el autoload LinkUx esté completamente listo
    await get_tree().process_frame
    _init_linkux()
    LinkUx.scene_load_requested.connect(_on_scene_load_requested)
    LinkUx.session_closed.connect(_on_session_closed)

func _init_linkux() -> void:
    if LinkUx.get_config() != null:
        return  # Ya inicializado; evita reinicializaciones duplicadas
    var config := LinkUxConfig.new()
    config.network = NetworkConfig.new()
    config.network.tick_rate = 30
    config.log_level = 3  # 0=none, 1=error, 2=warn, 3=info, 4=debug
    LinkUx.initialize(config)

func _on_scene_load_requested(scene_path: String) -> void:
    get_tree().change_scene_to_file(scene_path)

func _on_session_closed() -> void:
    get_tree().change_scene_to_file("res://scenes/menu.tscn")
```

---

<!-- doc-shell:page slug="configuracion" -->

# Configuración

LinkUx se configura mediante el recurso `LinkUxConfig`, que agrupa cuatro clases de configuración independientes.

## LinkUxConfig

Recurso principal. Se crea con `LinkUxConfig.new()` y se pasa a `LinkUx.initialize(config)`.

| Propiedad | Tipo | Por defecto | Descripción |
|-----------|------|-------------|-------------|
| `default_backend` | `NetworkEnums.BackendType` | `NONE` | Backend que se activa al llamar a `initialize()`. Si es `NONE`, debes llamar a `set_backend()` manualmente antes de crear o unirte a una sesión. |
| `network` | `NetworkConfig` | `null` | Ajustes de timing y optimización de red. |
| `lan` | `LanBackendConfig` | `null` | Configuración específica del backend LAN. |
| `advanced` | `AdvancedConfig` | `null` | Opciones avanzadas. |
| `debug_enabled` | `bool` | `false` | Activa hooks internos de debug. |
| `log_level` | `int` | `3` | Nivel de verbosidad del log (ver valores abajo). |

**Niveles de log:**

| Valor | Constante | Descripción |
|-------|-----------|-------------|
| `0` | `NONE` | Sin logs |
| `1` | `ERROR` | Solo errores |
| `2` | `WARN` | Errores y advertencias |
| `3` | `INFO` | Información general (recomendado en producción) |
| `4` | `DEBUG` | Detallado |
| `5` | `TRACE` | Muy verboso (solo desarrollo) |

---

## NetworkConfig

Controla el timing de red y las optimizaciones de transporte.

| Propiedad | Tipo | Por defecto | Descripción |
|-----------|------|-------------|-------------|
| `tick_rate` | `int` (1–128) | `20` | Ticks de red por segundo. Valores comunes: 20 (acción suave), 30 (FPS), 60 (alta precisión). |
| `interpolation_delay_ms` | `float` | `100.0` | Retraso de interpolación en ms. Aumentar reduce el jitter; disminuir reduce la latencia perceptible. |
| `extrapolation_limit_ms` | `float` | `250.0` | Límite de extrapolación en ms cuando no llegan paquetes. |
| `max_snapshot_buffer_size` | `int` (5–120) | `30` | Tamaño máximo del buffer de snapshots para interpolación. |
| `heartbeat_interval_ms` | `float` | `5000.0` | Intervalo entre heartbeats para detectar desconexiones. |
| `disconnect_timeout_ms` | `float` | `15000.0` | Tiempo sin heartbeat antes de considerar un peer desconectado. |
| `packet_batch_enabled` | `bool` | `true` | Agrupa múltiples paquetes por tick para reducir overhead. |
| `delta_compression_enabled` | `bool` | `true` | Solo envía propiedades que cambiaron desde el último tick. |
| `max_packet_size` | `int` | `4096` | Tamaño máximo de un paquete en bytes. |
| `max_rpc_per_tick` | `int` (1–100) | `10` | Máximo de RPCs que se procesan por tick. |

---

## LanBackendConfig

Opciones específicas del backend LAN (ENet).

| Propiedad | Tipo | Por defecto | Descripción |
|-----------|------|-------------|-------------|
| `default_port` | `int` | `7777` | Puerto base del servidor ENet. |
| `max_clients` | `int` | `16` | Máximo de clientes que puede aceptar el servidor. |
| `lan_port_stride` | `int` | `2` | Incremento de puerto si el puerto base ya está ocupado. Permite múltiples hosts en la misma máquina. |
| `max_lan_host_attempts` | `int` | `8` | Número de puertos alternativos a intentar al crear un servidor. |
| `in_bandwidth` | `int` | `0` | Ancho de banda de entrada máximo en bytes/s. `0` = ilimitado. |
| `out_bandwidth` | `int` | `0` | Ancho de banda de salida máximo en bytes/s. `0` = ilimitado. |
| `connection_timeout` | `float` | `3.0` | Segundos máximos para completar la conexión ENet del cliente. Si expira, se emite `connection_failed`. |

---

## AdvancedConfig

Opciones avanzadas de comportamiento.

| Propiedad | Tipo | Por defecto | Descripción |
|-----------|------|-------------|-------------|
| `enable_host_migration` | `bool` | `false` | Permite migrar el host si el host original se desconecta. |
| `max_reconnect_attempts` | `int` | `3` | Intentos de reconexión automática ante desconexiones inesperadas. |
| `reconnect_timeout_ms` | `float` | `10000.0` | Tiempo máximo por intento de reconexión en ms. |
| `ghost_player_timeout_ms` | `float` | `30000.0` | Tiempo antes de limpiar un peer "fantasma" que no completó la handshake. |
| `max_bandwidth_per_second` | `int` | `1024000` | Límite global de ancho de banda en bytes/s (~1 MB/s). |
| `max_state_updates_per_entity_per_tick` | `int` | `1` | Máximo de actualizaciones de estado por entidad y tick. |

---

## Ejemplo completo de configuración

```gdscript
func _init_linkux() -> void:
    var config := LinkUxConfig.new()

    # Red
    config.network = NetworkConfig.new()
    config.network.tick_rate = 30
    config.network.heartbeat_interval_ms = 3000.0
    config.network.disconnect_timeout_ms = 10000.0

    # LAN
    config.lan = LanBackendConfig.new()
    config.lan.default_port = 7777
    config.lan.connection_timeout = 5.0

    # Avanzado
    config.advanced = AdvancedConfig.new()

    # Debug
    config.debug_enabled = true
    config.log_level = 4  # DEBUG

    LinkUx.initialize(config)
```

---

<!-- doc-shell:page slug="sesiones" -->

# Sesiones

Una **sesión** es una sala de juego activa. El jugador que la crea es el **host**; el resto son **clientes**. Todo el flujo multijugador gira alrededor de la sesión.

## Ciclo de vida típico

```
set_backend()  →  create_session() / join_session_by_room_code()
      ↓
[señal session_started]
      ↓
request_scene_load()  →  report_scene_ready()  →  [señal scene_all_ready]
      ↓
[gameplay]
      ↓
close_session()  →  [señal session_closed]
```

---

## Métodos de sesión

### `LinkUx.set_backend(backend_type: int) → void`

Activa el backend de red especificado. Debe llamarse antes de crear o unirse a una sesión.

```gdscript
LinkUx.set_backend(NetworkEnums.BackendType.LAN)
```

---

### `LinkUx.create_session(session_name, max_players, metadata) → int`

Crea una sesión nueva (convierte al llamador en host).

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `session_name` | `String` | Nombre visible de la sala. |
| `max_players` | `int` | Límite de jugadores (default `16`). |
| `metadata` | `Dictionary` | Metadatos opcionales (`{"private": true}`, etc.). |

**Retorna:** `NetworkEnums.ErrorCode` — `SUCCESS (0)` si todo fue bien.

```gdscript
var err := LinkUx.create_session("Mi Sala", 4)
if err != NetworkEnums.ErrorCode.SUCCESS:
    print("Error: ", err)
```

---

### `LinkUx.join_session(session_info: SessionInfo) → int`

Se une a una sesión usando un objeto `SessionInfo` (obtenido de un listado de sesiones).

```gdscript
var err := LinkUx.join_session(session_info)
```

---

### `LinkUx.join_session_by_room_code(room_code: String) → int`

Se une a una sesión LAN usando el código de sala de 8 caracteres.

```gdscript
var code := $CodeInput.text.strip_edges().to_upper()
var err := LinkUx.join_session_by_room_code(code)
if err != NetworkEnums.ErrorCode.SUCCESS:
    print("Código inválido o sala no encontrada")
```

---

### `LinkUx.close_session() → void`

Cierra la sesión activa y desconecta a todos los peers. Emite la señal `session_closed`.

```gdscript
LinkUx.close_session()
```

---

### `LinkUx.prepare_for_new_session() → void`

Limpia el estado interno para permitir crear/unirse a una nueva sesión. Llama a esto cuando vuelves al menú principal para evitar errores de estado inválido.

```gdscript
# En el menú principal, al entrar
func _ready() -> void:
    LinkUx.prepare_for_new_session()
```

---

### Consultas de sesión

| Método | Retorna | Descripción |
|--------|---------|-------------|
| `get_current_session()` | `SessionInfo` | Objeto de la sesión activa (`null` si no hay sesión). |
| `get_room_code()` | `String` | Código de sala de la sesión actual. |
| `has_room()` | `bool` | `true` si hay una sesión activa. |
| `is_in_session()` | `bool` | `true` si la conexión está establecida y en sesión. |
| `is_host()` | `bool` | `true` si el peer local es el host. |
| `is_client()` | `bool` | `true` si el peer local es cliente (no host). |
| `is_singleplayer()` | `bool` | `true` si solo hay un jugador en la sesión. |
| `is_multiplayer()` | `bool` | `true` si hay más de un jugador. |
| `is_lan()` | `bool` | `true` si el backend activo es LAN. |

---

## SessionInfo — Estructura de datos

| Propiedad | Tipo | Descripción |
|-----------|------|-------------|
| `session_id` | `String` | ID único de la sesión. |
| `session_name` | `String` | Nombre de la sala. |
| `host_peer_id` | `int` | ID de red del host (siempre `1` en LAN). |
| `max_players` | `int` | Límite de jugadores configurado al crear. |
| `room_code` | `String` | Código alfanumérico de sala. |
| `backend_data` | `Dictionary` | Datos opacos del backend (p.ej. IP:puerto en LAN). |

---

## Códigos de error (NetworkEnums.ErrorCode)

| Código | Valor | Descripción |
|--------|-------|-------------|
| `SUCCESS` | `0` | Operación exitosa. |
| `NETWORK_UNAVAILABLE` | `101` | Sin red disponible. |
| `SESSION_NOT_FOUND` | `102` | Código de sala no encontrado. |
| `SESSION_FULL` | `103` | La sala está llena. |
| `AUTHORITY_DENIED` | `104` | Operación de autoridad rechazada. |
| `PROTOCOL_VERSION_MISMATCH` | `106` | Versión de protocolo incompatible. |
| `BACKEND_NOT_SET` | `113` | No se ha configurado un backend antes de crear/unirse. |
| `ALREADY_IN_SESSION` | `114` | Ya hay una sesión activa. Llama a `close_session()` primero. |

---

## Ejemplo — Menú principal

```gdscript
extends Control

func _ready() -> void:
    LinkUx.prepare_for_new_session()
    LinkUx.session_started.connect(_on_session_started)
    LinkUx.connection_failed.connect(_on_connection_failed)

func _on_host_btn_pressed() -> void:
    LinkUx.set_local_player_name($NicknameInput.text)
    LinkUx.set_backend(NetworkEnums.BackendType.LAN)
    var err := LinkUx.create_session("Sala de %s" % $NicknameInput.text, 4)
    if err != NetworkEnums.ErrorCode.SUCCESS:
        _show_error("No se pudo crear la sala (error %d)" % err)

func _on_join_btn_pressed() -> void:
    LinkUx.set_local_player_name($NicknameInput.text)
    LinkUx.set_backend(NetworkEnums.BackendType.LAN)
    var err := LinkUx.join_session_by_room_code($CodeInput.text.strip_edges())
    if err != NetworkEnums.ErrorCode.SUCCESS:
        _show_error("Código inválido o sala no encontrada")

func _on_session_started() -> void:
    if LinkUx.is_host():
        LinkUx.request_scene_load("res://scenes/level.tscn")

func _on_connection_failed(error: String) -> void:
    _show_error("Error de conexión: " + error)
```

---

<!-- doc-shell:page slug="jugadores" -->

# Jugadores y Perfiles

LinkUx mantiene un registro de todos los jugadores conectados como objetos `PlayerInfo`. Puedes consultar y modificar estos datos en cualquier momento.

## Perfil del jugador local

### `LinkUx.set_local_player_name(display_name: String) → void`

Establece el nombre del jugador local. Llama a esto **antes** de crear o unirte a una sesión.

```gdscript
LinkUx.set_local_player_name("Zara")
```

### `LinkUx.set_player_profile(display_name, metadata, data) → void`

Versión extendida que permite añadir metadatos y datos personalizados.

```gdscript
LinkUx.set_player_profile(
    "Zara",
    {"avatar": "warrior"},      # metadata: visible para todos
    {"score": 0, "level": 1}    # data: estado interno
)
```

### `LinkUx.get_local_player_name() → String`

Retorna el nombre del jugador local.

---

## Consultar jugadores

| Método | Retorna | Descripción |
|--------|---------|-------------|
| `get_local_player()` | `PlayerInfo` | Datos del jugador local. |
| `get_player_info(peer_id)` | `PlayerInfo` | Datos de un peer específico por ID. `null` si no existe. |
| `get_players()` | `Array[PlayerInfo]` | Todos los jugadores conectados (incluido el local). |
| `get_remote_players()` | `Array[PlayerInfo]` | Solo los jugadores remotos (excluye al local). |
| `get_host_player()` | `PlayerInfo` | Datos del jugador que es host. |
| `get_client_players()` | `Array[PlayerInfo]` | Solo los clientes (excluye al host). |
| `get_local_peer_id()` | `int` | ID de red del peer local. |
| `get_connected_peers()` | `Array[int]` | IDs de todos los peers conectados. |
| `is_local_player_id(peer_id)` | `bool` | `true` si el `peer_id` corresponde al jugador local. |
| `is_local_player_info(info)` | `bool` | `true` si el `PlayerInfo` corresponde al jugador local. |
| `is_player_connected(peer_id)` | `bool` | `true` si el peer está en la sesión activa. |

---

## Datos dinámicos por jugador

Puedes almacenar datos personalizados en cada jugador en tiempo de ejecución:

### `LinkUx.update_local_player_data(key: String, value: Variant) → void`

```gdscript
LinkUx.update_local_player_data("score", 150)
LinkUx.update_local_player_data("ready", true)
```

### `LinkUx.remove_local_player_data(key: String) → void`

```gdscript
LinkUx.remove_local_player_data("ready")
```

### `LinkUx.set_player_data(peer_id, key, value) → bool`

Modifica los datos de cualquier jugador (solo localmente, no se sincroniza automáticamente).

### `LinkUx.get_player_data(peer_id) → Dictionary`

```gdscript
var data := LinkUx.get_player_data(peer_id)
print("Puntuación: ", data.get("score", 0))
```

### `LinkUx.remove_player_data(peer_id, key) → bool`

---

## Patear a un jugador

### `LinkUx.kick_player(peer_id: int, reason: String) → void`

Solo el host puede patear jugadores. El cliente pateado recibe `reason` como mensaje de error en la señal `connection_failed`.

```gdscript
# Solo válido desde el host
if LinkUx.is_host():
    LinkUx.kick_player(peer_id, "Comportamiento inapropiado")
```

---

## PlayerInfo — Estructura de datos

| Propiedad | Tipo | Descripción |
|-----------|------|-------------|
| `peer_id` | `int` | ID de red único del jugador en la sesión. |
| `display_name` | `String` | Nombre visible del jugador. |
| `is_host` | `bool` | `true` si este jugador es el host. |
| `metadata` | `Dictionary` | Metadatos configurados en `set_player_profile`. |
| `data` | `Dictionary` | Datos dinámicos actualizables en tiempo real. |

---

## Ejemplo — Mostrar lista de jugadores

```gdscript
func _actualizar_lista_jugadores() -> void:
    for info in LinkUx.get_players():
        var etiqueta := Label.new()
        var prefijo := "[HOST] " if info.is_host else ""
        var tuyo := " (tú)" if LinkUx.is_local_player_info(info) else ""
        etiqueta.text = prefijo + info.display_name + tuyo
        $ListaJugadores.add_child(etiqueta)
```

---

<!-- doc-shell:page slug="entidades" -->

# Entidades — LinkUxEntity

`LinkUxEntity` es un nodo que convierte a su padre en una **entidad replicada**. Al agregarlo como hijo de cualquier nodo, LinkUx comenzará a sincronizar sus propiedades con todos los peers de la sesión.

## Cuándo usar LinkUxEntity vs LinkUxSynchronizer

| | `LinkUxEntity` | `LinkUxSynchronizer` |
|--|--|--|
| **Interpolación** | No (el estado remoto se aplica directamente) | Sí (suavizado en `_process` para peers que no son dueños) |
| **Uso típico** | Objetos que el host controla por completo; estados discretos | Personajes y props con movimiento continuo visto en remoto |
| **Lista de propiedades** | `replicated_properties` (`PackedStringArray` en el inspector) | `sync_properties` (`Array[String]`, más editor personalizado) |
| **Modo de replicación por defecto** | `ON_CHANGE` | `ALWAYS` |

Usa **`LinkUxSynchronizer`** para personajes u objetos donde los clientes deben ver **movimiento suave** (lerp / `lerp_angle` en posición y rotación). Usa **`LinkUxEntity`** para objetos cuyo estado puede aplicarse **a saltos** (puertas, interruptores, contadores, animaciones disparadas por valores discretos).

### No combines ambos en el mismo nodo raíz

`LinkUxEntity` y `LinkUxSynchronizer` registran al **nodo padre** con `LinkUx.register_entity(...)`. Si añades **los dos como hijos del mismo** `CharacterBody3D` (u otro raíz), ambos intentarán registrar las mismas rutas y propiedades: obtendrás comportamiento imprevisto y advertencias en consola. Elige **uno u otro** por entidad replicada.

---

## Propiedades exportadas

| Propiedad | Tipo | Por defecto | Descripción |
|-----------|------|-------------|-------------|
| `authority_mode` | `NetworkEnums.AuthorityMode` | `HOST` | Define quién tiene la **autoridad** lógica del nodo padre ante LinkUx (host, dueño o transferible). El `AuthorityManager` aplicará el `peer_id` correspondiente al entrar en sesión. |
| `replicated_properties` | `PackedStringArray` | `[]` | Nombres de propiedades del **padre** que se envían por red. Solo rutas simples (`"health"`, `"global_position"`); **no** usa la sintaxis `Hijo:propiedad` (eso es del Synchronizer). |
| `replication_mode` | `NetworkEnums.ReplicationMode` | `ON_CHANGE` | `ALWAYS`: cada tick; `ON_CHANGE`: solo si el valor cambió respecto al último envío; `MANUAL`: el replicador no manda hasta que lo invoques explícitamente desde código avanzado. |

### Modos de autoridad (AuthorityMode)

| Modo | Descripción |
|------|-------------|
| `HOST` | El host tiene autoridad absoluta. Los clientes reciben estado pero no pueden modificarlo. Ideal para objetos del mundo (puertas, proyectiles del servidor). |
| `OWNER` | El peer que spawneó la entidad tiene autoridad. Ideal para personajes de jugador. |
| `TRANSFERABLE` | La autoridad puede transferirse dinámicamente entre peers. Útil para objetos recogibles. |

### Modos de replicación (ReplicationMode)

| Modo | Descripción |
|------|-------------|
| `ALWAYS` | Envía actualizaciones cada tick aunque el valor no haya cambiado. Mayor uso de ancho de banda. |
| `ON_CHANGE` | Solo envía cuando el valor cambia respecto al último tick. Recomendado para la mayoría de casos. |
| `MANUAL` | Solo envía cuando se solicita explícitamente con `register_entity()`. Para objetos de estado muy infrecuente. |

---

## Cómo usar en el editor

1. Abre la escena del objeto que debe existir en todos los peers (por ejemplo un cofre o una puerta en el nivel, o un personaje **no** basado en `LinkUxSpawner`).
2. Selecciona el **nodo raíz** que posee las variables que quieres replicar (`StaticBody3D`, `Area3D`, `CharacterBody3D`, etc.).
3. Clic derecho → **Añadir hijo** → **`LinkUxEntity`** (categoría del addon).
4. En el inspector del `LinkUxEntity`:
   - **`Authority mode`:** elige `HOST` para objetos del mundo; `OWNER` si la entidad “pertenece” al peer que la creó; `TRANSFERABLE` si usarás `request_authority` / `transfer_authority`.
   - **`Replicated properties`:** edita el `PackedStringArray` y escribe cada nombre **exactamente** como en el script (`health`, `is_open`, `global_position`, …). Deben ser propiedades existentes en el padre y serializables por el replicador.
   - **`Replication mode`:** deja `ON_CHANGE` salvo que necesites muestreo fijo cada tick (`ALWAYS`).

```
CharacterBody3D  ← nodo a replicar
└── LinkUxEntity
    authority_mode: OWNER
    replicated_properties: ["position", "rotation", "health"]
```

### Momento del registro

`LinkUxEntity` llama a `_register()` en diferido (`call_deferred`). Solo se registra en el `StateReplicator` si **`LinkUx.is_in_session()`** es verdadero cuando el nodo entra en el árbol. Si instancias la escena **antes** de crear/unirte a la sesión, el nodo quedará sin registrar hasta la próxima carga en sesión; el patrón habitual es cargar el gameplay **después** de `session_started` / `scene_all_ready`.

---

## Registro automático

`LinkUxEntity` se registra automáticamente con el `StateReplicator` al entrar al árbol de escena (si ya hay una sesión activa). También se desregistra automáticamente al salir del árbol. No necesitas llamar a ningún método manualmente.

---

## Ejemplo — Objeto del mundo controlado por el host

```gdscript
# door.gd
extends StaticBody3D

var is_open: bool = false

func toggle() -> void:
    if not LinkUx.is_host():
        return  # Solo el host puede abrir/cerrar
    is_open = not is_open
    _update_visual()

func _update_visual() -> void:
    $AnimationPlayer.play("open" if is_open else "close")
```

```
StaticBody3D (door.gd)
└── LinkUxEntity
    authority_mode: HOST
    replicated_properties: ["is_open"]
    replication_mode: ON_CHANGE
```

---

<!-- doc-shell:page slug="sincronizador" -->

# Sincronizador — LinkUxSynchronizer

`LinkUxSynchronizer` es el componente de sincronización pensado para **entidades con movimiento continuo** (sobre todo personajes). A diferencia de `LinkUxEntity`, aplica **interpolación** en clientes cuando el estado no es del jugador local: los valores de red no se copian de golpe, sino que convergen suavemente en `_process`.

## Propiedades exportadas

| Propiedad | Tipo | Por defecto | Descripción |
|-----------|------|-------------|-------------|
| `sync_properties` | `Array[String]` | `[]` | Lista de propiedades que el `StateReplicator` observará en el **padre** del Synchronizer. Acepta propiedades del padre (`"position"`) o de nodos hijos con la forma `"Camino/Del/Nodo:propiedad"`. |
| `replication_mode` | `NetworkEnums.ReplicationMode` | `ALWAYS` | Por defecto reenvía cada tick (adecuado a movimiento). Puedes pasar a `ON_CHANGE` si solo algunas claves cambian y quieres ahorrar ancho de banda. |
| `interpolate` | `bool` | `true` | Si es `true`, los peers **que no son dueños** mezclan el estado recibido con `lerp` / `lerp_angle`. Si es `false`, cada snapshot se aplica de inmediato (`_flush_state_to_target`). |
| `remote_smoothing_hz` | `float` (2–45) | `16.0` | Factor de suavizado: en cada frame se avanza un paso `clampf(remote_smoothing_hz * delta, 0, 1)` hacia el valor remoto. Valores **más altos** siguen más de cerca al último paquete (menos “retraso” visual), valores **más bajos** suavizan más. |

### Variables adicionales (solo por código)

| Variable | Tipo | Por defecto | Descripción |
|----------|------|-------------|-------------|
| `position_snap_epsilon` | `float` | `0.0002` | Si la distancia al objetivo es menor que este umbral, la posición se **ajusta exactamente** y se deja de interpolar esa clave. |
| `rotation_snap_epsilon` | `float` | `0.0002` | Igual para rotaciones; en `rotation` (Vector3) usa `lerp_angle` por componente para evitar giros de 360°. |

---

## Añadir propiedades desde el inspector

El addon sustituye el editor por defecto de `sync_properties` por un **panel personalizado** (plugin `linkux_sync_inspector_plugin.gd`):

1. Selecciona el nodo **`LinkUxSynchronizer`** en el árbol de escena.
2. En el inspector verás la sección **“Propiedades sincronizadas”** / *Synchronized Properties* (texto según el idioma del editor).
3. Lista central: cada fila es una propiedad. Muestra iconos del tipo de nodo y del tipo de dato, la ruta (`Pivot › rotation`) y un botón para **eliminar** la entrada.
4. Pulsa **`Añadir propiedad sincronizada`** / **Add Sync Property**:
   - Se abre un diálogo con el **árbol de la escena** a la izquierda y las **propiedades** del nodo elegido a la derecha.
   - Filtra con la barra de búsqueda si la lista es larga.
   - Doble clic en una propiedad, o selecciónala y confirma con **`Añadir propiedad`**.
   - Si eliges una propiedad del **mismo nodo padre** que el Synchronizer, se guarda como `"nombre_prop"`. Si eliges un hijo, como `"Hijo:propiedad"` o `"Ruta/Completa:propiedad"`.
5. **`Actualizar lista`** fuerza un refresco si cambiaste nodos en la escena y el inspector no se ha enterado.
6. Las acciones pasan por **deshacer / rehacer** del editor (`EditorUndoRedoManager`).

La fila se marca en **naranja** si el segmento de ruta de nodo ya no existe: revisa el nombre o vuelve a abrir el selector.

> También puedes editar el `Array[String]` en modo crudo desde el **script** o duplicar nodos, pero el flujo recomendado es el diálogo para evitar typos.

### Dueño del estado (local vs remoto)

El Synchronizer usa la misma regla que el resto de LinkUx para saber si **tú** eres quien mueve la entidad:

- Si el padre tiene `player_peer_id`, se compara con `LinkUx.get_local_peer_id()`.
- Si no, se usa `LinkUx.is_entity_authority(nodo_padre)` cuando exista autoridad registrada.

Si eres el dueño, **`apply_remote_state` vacía los pendientes** y no sobrescribe tu simulación. Los demás peers interpolan lo que envías.

---

## Formato de `sync_properties`

```gdscript
sync_properties = [
    "position",                        # Propiedad directa del padre
    "rotation",                        # Propiedad directa del padre
    "health",                          # Cualquier propiedad exportada
    "Head:rotation",                   # Propiedad de un nodo hijo llamado "Head"
    "WeaponHolder/Gun:position",       # Subruta de nodo hijo
]
```

> **Nota:** Solo sincroniza propiedades que Godot pueda serializar: `int`, `float`, `bool`, `String`, `Vector2`, `Vector3`, `Quaternion`, `Color`, etc.

---

## Cómo funciona la interpolación

Cuando llega un estado remoto, el Synchronizer no aplica los valores inmediatamente. En cambio, los guarda como `_pending_state` y en cada frame `_process()` hace un `lerp` hacia el objetivo:

```
Estado recibido → _pending_state
_process() → lerp(posición_actual, objetivo, remote_smoothing_hz * delta)
```

La rotación usa `lerp_angle()` para manejar correctamente el corte ±π (evita rotaciones de 360°).

Solo se interpolan los objetos remotos. El dueño local aplica los valores al instante.

---

## Regla: un Synchronizer por nodo

Solo puede haber **un** `LinkUxSynchronizer` activo por nodo padre. Si añades más de uno, el sistema emitirá un warning y solo el primero (en orden de hijos) será el primario:

```
[LinkUx] WARN: Multiple synchronizers detected under 'Player'.
               'Synchronizer2' will be ignored; primary is 'Synchronizer'.
```

---

## Ejemplo — Jugador con movimiento suave

```
Player (CharacterBody3D)
└── LinkUxSynchronizer
    sync_properties: ["position", "rotation", "player_nickname", "Pivot:rotation"]
    interpolate: true
    remote_smoothing_hz: 24.0
```

```gdscript
# player.gd
extends CharacterBody3D

@export var player_peer_id: int = 0
@export var player_nickname: String = ""

func _ready() -> void:
    if not LinkUx.is_local_player_id(player_peer_id):
        set_process_unhandled_input(false)
        return
    # Solo para el jugador local: configurar cámara, etc.
    $Camera3D.current = true

func _physics_process(_delta: float) -> void:
    if not LinkUx.is_local_player_id(player_peer_id):
        return
    var dir := Vector3(
        Input.get_axis("move_left", "move_right"),
        0,
        Input.get_axis("move_forward", "move_back")
    )
    velocity = dir.normalized() * 5.0
    move_and_slide()
```

---

<!-- doc-shell:page slug="spawner" -->

# Spawner — LinkUxSpawner

`LinkUxSpawner` replica el **spawn y despawn de escenas** en todos los peers de la sesión. Es el sistema recomendado para crear jugadores, proyectiles, ítems y cualquier objeto dinámico en multijugador.

## Propiedades exportadas

| Propiedad | Tipo | Descripción |
|-----------|------|-------------|
| `spawn_path` | `NodePath` | Ruta (relativa al Spawner) al nodo bajo el que se colocarán las instancias, p. ej. `Players` o `../Entities`. Si se deja **vacío** (`NodePath("")`), las escenas se cuelgan directamente del **padre del Spawner**. |
| `spawnable_scenes` | `Array[PackedScene]` | Escenas permitidas. El índice que pasas a `spawn()` corresponde a la posición en este array (`0` = primer elemento). Mantén órdenes idénticos en todas las máquinas (misma escena de proyecto). |

### Configuración en el inspector

1. Crea un nodo contenedor (por ejemplo `Players`) en la escena del nivel.
2. Añade **`LinkUxSpawner`** como hijo del nivel (o donde te sea cómodo).
3. Arrastra el contenedor al campo **`Spawn Path`** o escribe la ruta relativa (`Players`).
4. En **`Spawnable Scenes`**, asigna cada `PackedScene` (`.tscn`) en el orden que usarás en código.

---

## Métodos

### `spawn(scene_index, properties, authority_peer) → Node`

Instancia la escena en el índice dado, aplica las propiedades y replica a todos los peers.

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `scene_index` | `int` | Índice en `spawnable_scenes`. |
| `properties` | `Dictionary` | Propiedades a aplicar antes de `_ready()`. |
| `authority_peer` | `int` | Peer que tendrá autoridad sobre la entidad. Default `1` (host). |

```gdscript
var jugador := $PlayerSpawner.spawn(
    0,  # índice 0 en spawnable_scenes = player.tscn
    {
        "player_peer_id": LinkUx.get_local_peer_id(),
        "player_nickname": LinkUx.get_local_player_name(),
        "global_position": Vector3(0, 1, 0),
    },
    LinkUx.get_local_peer_id()
)
```

> **Importante:** Las propiedades que NO son de transformación (`position`, `rotation`, etc.) se aplican **antes** de `add_child()`, para que el nodo se configure correctamente en `_ready()`.

---

### `despawn(entity: Node) → void`

Elimina la entidad localmente y notifica a todos los peers para que también la eliminen.

```gdscript
$PlayerSpawner.despawn(mi_jugador)
```

---

### `unicast_spawn_to_peer(scene_index, properties, authority_peer, target_peer, spawn_id) → void`

Envía un spawn solo a un peer específico. Útil internamente para late-join, pero también puedes usarlo para spawnear entidades que solo ciertos peers deben ver.

---

## Comportamiento automático

### Despawn al desconectarse

Cuando un peer se desconecta, el Spawner (en el host) elimina automáticamente todas las entidades cuyo `authority_peer` sea el peer desconectado. No necesitas programar esto.

### Late join — Replay de spawns

Cuando un jugador se une tarde a una sesión en curso, el host envía automáticamente todos los spawns existentes al nuevo jugador. El mundo es consistente sin código adicional.

---

## Setup en el editor

```
Level (Node3D)
├── PlayerSpawner (LinkUxSpawner)
│   spawn_path: Players         ← NodePath relativa
│   spawnable_scenes: [player.tscn]
└── Players (Node3D)            ← Los jugadores se crean aquí
```

---

## Ejemplo — Spawn de jugadores en el nivel

```gdscript
# level.gd
extends Node3D

@onready var spawner: LinkUxSpawner = $PlayerSpawner

func _ready() -> void:
    LinkUx.player_joined.connect(_on_player_joined)
    LinkUx.player_left_processed.connect(_on_player_left)

    # Spawnear el jugador local
    _spawn_player(LinkUx.get_local_peer_id())
    LinkUx.report_scene_ready()

func _on_player_joined(info: PlayerInfo) -> void:
    # No spawnear al jugador local de nuevo
    if info.peer_id == LinkUx.get_local_peer_id():
        return
    _spawn_player(info.peer_id)

func _on_player_left(_info: PlayerInfo, _reason: int) -> void:
    pass  # El Spawner elimina la entidad automáticamente

func _spawn_player(peer_id: int) -> void:
    spawner.spawn(0, {
        "player_peer_id": peer_id,
        "player_nickname": LinkUx.get_player_info(peer_id).display_name,
        "global_position": _get_spawn_point(),
    }, peer_id)

func _get_spawn_point() -> Vector3:
    return Vector3(randf_range(-4.0, 4.0), 1.0, randf_range(-4.0, 4.0))

func _unhandled_key_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel"):
        LinkUx.close_session()
```

---

<!-- doc-shell:page slug="rpc" -->

# Sistema RPC

LinkUx proporciona un sistema de **llamadas a procedimiento remoto** (RPC) completamente independiente del sistema RPC de Godot. Las RPCs de LinkUx se enrutan a través del `RpcRelay` y admiten tanto modo fiable como no fiable.

## Métodos de envío

### Envío dirigido

```gdscript
# Enviar a un peer específico
LinkUx.send_rpc(peer_id, "mi_metodo", [arg1, arg2], true)

# Enviar al host
LinkUx.send_rpc_to_host("mi_metodo", [arg1])
```

### Broadcast

```gdscript
# Enviar a todos los peers (incluido el local)
LinkUx.broadcast_rpc("actualizar_puntuacion", [peer_id, puntuacion])
```

### Atajos de alto nivel

| Método | Descripción |
|--------|-------------|
| `send_to_all(method, payload, reliable)` | Broadcast a todos. |
| `send_to_host(method, payload, reliable)` | Al host (peer ID 1). |
| `send_to_player(peer_id, method, payload, reliable)` | A un jugador específico. |
| `send_to_clients(method, payload, reliable)` | A todos los clientes (excluye al host). |

> Los métodos `send_to_*` envuelven el `payload` en un array automáticamente si no lo es.

---

## Registrar handlers

Para recibir RPCs, debes registrar un handler con el nombre del método:

```gdscript
func _ready() -> void:
    LinkUx.register_rpc("recibir_mensaje", _on_recibir_mensaje)

func _on_recibir_mensaje(from_peer: int, mensaje: String) -> void:
    print("[%s]: %s" % [from_peer, mensaje])
```

> **Nota:** El primer argumento del handler siempre es `from_peer: int` (el ID del remitente), seguido de los argumentos enviados.

### Desregistrar un handler

```gdscript
LinkUx.unregister_rpc("recibir_mensaje")
```

---

## Modo fiable vs no fiable

| Parámetro | Valor | Descripción |
|-----------|-------|-------------|
| `reliable` | `true` | ENet garantiza la entrega y el orden. Úsalo para eventos críticos (spawn, muerte, puntaje). |
| `reliable` | `false` | Paquetes UDP sin garantía. Menor latencia, puede perderse. Úsalo para actualizaciones de posición frecuentes. |

---

## Ejemplo — Sistema de chat

```gdscript
# chat.gd
extends Control

func _ready() -> void:
    LinkUx.register_rpc("chat_mensaje", _on_chat_mensaje)

func _exit_tree() -> void:
    LinkUx.unregister_rpc("chat_mensaje")

func _on_send_btn_pressed() -> void:
    var msg := $Input.text.strip_edges()
    if msg.is_empty():
        return
    var nombre := LinkUx.get_local_player_name()
    # Enviar a todos (incluido yo mismo para verlo en mi pantalla)
    LinkUx.broadcast_rpc("chat_mensaje", [nombre, msg])
    $Input.text = ""

func _on_chat_mensaje(_from_peer: int, nombre: String, mensaje: String) -> void:
    $Log.text += "\n[%s]: %s" % [nombre, mensaje]
```

---

<!-- doc-shell:page slug="estado-global" -->

# Estado Global

El **estado global** es un diccionario clave-valor sincronizado con todos los peers. Solo el host puede modificarlo; los clientes lo reciben automáticamente y pueden consultarlo en cualquier momento.

## Métodos

### `LinkUx.set_global_state(key: String, value: Variant) → void`

Establece un valor en el estado global y lo replica a todos los peers.

```gdscript
# Solo desde el host
if LinkUx.is_host():
    LinkUx.set_global_state("fase_juego", "combate")
    LinkUx.set_global_state("tiempo_restante", 120)
    LinkUx.set_global_state("puntuaciones", {"Zara": 0, "Leo": 0})
```

### `LinkUx.get_global_state(key: String, default: Variant = null) → Variant`

Lee un valor del estado global. Si la clave no existe, retorna `default`.

```gdscript
var fase: String = LinkUx.get_global_state("fase_juego", "espera")
var tiempo: int   = LinkUx.get_global_state("tiempo_restante", 0)
```

---

## Señal `global_state_changed`

Cuando cualquier valor del estado global cambia, se emite esta señal en todos los peers:

```gdscript
func _ready() -> void:
    LinkUx.global_state_changed.connect(_on_estado_cambiado)

func _on_estado_cambiado(key: String, value: Variant) -> void:
    match key:
        "fase_juego":
            _cambiar_fase(value)
        "tiempo_restante":
            $HUD/Timer.text = str(value)
```

---

## Casos de uso

- **Fases del juego**: `"lobby"`, `"contando"`, `"combate"`, `"fin"`
- **Contador regresivo** sincronizado
- **Tabla de puntuaciones** global
- **Configuración de la partida**: número de rondas, dificultad, mapa elegido
- **Semillas aleatorias** para generación procedural consistente

---

## Ejemplo — Contador de ronda

```gdscript
# game_manager.gd (solo se ejecuta en el host)
extends Node

var ronda_actual := 0

func _ready() -> void:
    if not LinkUx.is_host():
        return
    LinkUx.global_state_changed.connect(_on_estado_cambiado)
    iniciar_ronda()

func iniciar_ronda() -> void:
    ronda_actual += 1
    LinkUx.set_global_state("ronda", ronda_actual)
    LinkUx.set_global_state("fase", "jugando")

func terminar_ronda() -> void:
    LinkUx.set_global_state("fase", "fin_ronda")

func _on_estado_cambiado(key: String, _value: Variant) -> void:
    if key == "fase" and _value == "fin_ronda":
        await get_tree().create_timer(3.0).timeout
        iniciar_ronda()
```

---

<!-- doc-shell:page slug="autoridad" -->

# Autoridad de Entidades

La **autoridad** determina qué peer tiene control sobre una entidad replicada. Solo el peer con autoridad puede enviar actualizaciones de estado para esa entidad; los demás reciben esas actualizaciones y las aplican.

## Métodos

### `LinkUx.set_entity_authority(entity: Node, peer_id: int) → void`

Asigna la autoridad sobre una entidad a un peer específico.

```gdscript
# El host asigna autoridad sobre un objeto al jugador 2
LinkUx.set_entity_authority($ObjetoCentral, 2)
```

### `LinkUx.get_entity_authority(entity: Node) → int`

Retorna el `peer_id` del peer que tiene autoridad. `-1` si no está registrada.

```gdscript
var dueño := LinkUx.get_entity_authority(entidad)
```

### `LinkUx.is_entity_authority(entity: Node) → bool`

`true` si el peer local tiene autoridad sobre la entidad.

```gdscript
func _physics_process(_delta: float) -> void:
    if not LinkUx.is_entity_authority(self):
        return  # No procesar si no somos el dueño
    # ... lógica de física
```

### `LinkUx.request_authority(entity: Node) → void`

El peer local solicita la autoridad sobre una entidad (requiere que el modo sea `TRANSFERABLE`).

```gdscript
# Jugador intenta coger un ítem
LinkUx.request_authority($Item)
```

### `LinkUx.transfer_authority(entity: Node, to_peer_id: int) → void`

Transfiere la autoridad a otro peer (solo válido desde el peer con autoridad actual o el host).

```gdscript
# Host transfiere control de un vehículo al jugador que lo monta
LinkUx.transfer_authority($Vehiculo, peer_id_del_conductor)
```

### `LinkUx.validate_authority_change(entity: Node, peer_id: int) → bool`

Verifica si es válido transferir autoridad a ese peer.

---

## Modos de autoridad comparados

| Modo | Control | Caso de uso |
|------|---------|-------------|
| `HOST` | El host siempre tiene autoridad. | Objetos del mundo, enemigos controlados por servidor, puertas, trampas. |
| `OWNER` | El peer que spawneó la entidad. | Personajes de jugador, proyectiles del jugador. |
| `TRANSFERABLE` | Se puede pasar entre peers. | Vehículos, ítems recogibles, objetos de interacción. |

---

## Ejemplo — Ítem recogible transferible

```gdscript
# item.gd
extends Area3D

func _ready() -> void:
    body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
    if not body.has_method("get") or not "player_peer_id" in body:
        return
    if not LinkUx.is_host():
        return  # Solo el host decide quién recoge

    var peer_id: int = body.player_peer_id
    LinkUx.transfer_authority(self, peer_id)
    # El nuevo dueño puede decidir qué hacer con el ítem
```

```
Area3D (item.gd)
└── LinkUxEntity
    authority_mode: TRANSFERABLE
    replicated_properties: ["visible", "global_position"]
```

---

<!-- doc-shell:page slug="senales" -->

# Señales

LinkUx expone **26 señales** que cubren todo el ciclo de vida multiplayer. Conéctate a ellas para reaccionar a eventos de red sin necesidad de polling.

## Sesión

| Señal | Parámetros | Cuándo se emite |
|-------|------------|-----------------|
| `session_created` | `session_info: SessionInfo` | El host ha creado exitosamente la sesión. |
| `session_joined` | `session_info: SessionInfo` | El cliente se ha unido exitosamente a la sesión. |
| `session_started` | — | La sesión está lista (se emite en host Y cliente tras `session_created`/`session_joined`). Úsala para iniciar la carga de escena. |
| `session_closed` | — | La sesión se cerró (por `close_session()` o desconexión del host). |
| `session_ended` | — | Emitida internamente al finalizar la limpieza de sesión. |

## Jugadores

| Señal | Parámetros | Cuándo se emite |
|-------|------------|-----------------|
| `player_joined` | `player_info: PlayerInfo` | Un peer nuevo (incluido el propio) entró a la sesión. |
| `player_left` | `peer_id: int, reason: int` | Un peer se desconectó (antes de la limpieza). |
| `player_left_processed` | `player_info: PlayerInfo, reason: int` | Un peer se desconectó (después de limpiar su estado). Úsala para UI. |
| `player_updated` | `player_info: PlayerInfo` | Los datos de un jugador cambiaron (nombre, metadata, data). |

## Conexión

| Señal | Parámetros | Cuándo se emite |
|-------|------------|-----------------|
| `connection_failed` | `error: String` | Falló el intento de conectar/crear sesión. |
| `connection_state_changed` | `new_state: int` | El estado de conexión cambió. Ver `NetworkEnums.ConnectionState`. |
| `protocol_version_mismatch` | `local: int, remote: int` | El cliente tiene una versión de protocolo incompatible con el host. |
| `backend_incompatible` | `reason: String` | El backend activo no soporta las capacidades requeridas. |

## Carga de escena

| Señal | Parámetros | Cuándo se emite |
|-------|------------|-----------------|
| `scene_load_requested` | `scene_path: String` | El host solicita que todos carguen una escena. |
| `scene_all_ready` | `scene_path: String` | Todos los peers reportaron escena lista con `report_scene_ready()`. |

## Entidades y estado

| Señal | Parámetros | Cuándo se emite |
|-------|------------|-----------------|
| `authority_changed` | `entity: Node, new_authority: int` | La autoridad de una entidad cambió. |
| `global_state_changed` | `key: String, value: Variant` | Un valor del estado global cambió. |

## Red

| Señal | Parámetros | Cuándo se emite |
|-------|------------|-----------------|
| `network_tick` | `tick_number: int, delta: float` | Cada tick de red. Útil para lógica dependiente del tick. |

## Debug e interno

| Señal | Parámetros | Cuándo se emite |
|-------|------------|-----------------|
| `feedback_log_added` | `entry: Dictionary` | Se añadió una entrada al log interno. |
| `late_join_spawn_replay_needed` | `peer_id: int` | (Solo host) Un peer hizo late-join y necesita el replay de spawns. `LinkUxSpawner` lo gestiona automáticamente. |

---

## Ejemplo — Conectar señales esenciales

```gdscript
func _ready() -> void:
    LinkUx.session_started.connect(_on_session_started)
    LinkUx.session_closed.connect(_on_session_closed)
    LinkUx.connection_failed.connect(_on_connection_failed)
    LinkUx.player_joined.connect(_on_player_joined)
    LinkUx.player_left_processed.connect(_on_player_left)

func _on_session_started() -> void:
    print("Sesión iniciada. Host: ", LinkUx.is_host())

func _on_session_closed() -> void:
    get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _on_connection_failed(error: String) -> void:
    $UI/ErrorLabel.text = "Error: " + error

func _on_player_joined(info: PlayerInfo) -> void:
    print("Jugador entró: ", info.display_name, " (", info.peer_id, ")")

func _on_player_left(info: PlayerInfo, reason: int) -> void:
    print("Jugador salió: ", info.display_name)
```

---

<!-- doc-shell:page slug="api" -->

# Referencia de API

Referencia completa de todos los métodos públicos del Autoload `LinkUx`.

## Configuración

| Método | Retorna | Descripción |
|--------|---------|-------------|
| `initialize(config)` | `int` | Inicializa LinkUx con la config dada. Retorna `ErrorCode`. |
| `set_backend(backend_type)` | `void` | Activa el backend especificado. |
| `get_config()` | `LinkUxConfig` | Config activa (`null` si no inicializado). |
| `get_protocol_version()` | `int` | Versión del protocolo interno. |
| `get_backend_type()` | `int` | Tipo de backend activo (`NetworkEnums.BackendType`). |
| `get_backend_name()` | `String` | Nombre legible del backend activo. |

## Sesión

| Método | Retorna | Descripción |
|--------|---------|-------------|
| `prepare_for_new_session()` | `void` | Limpia estado para una nueva sesión. |
| `create_session(name, max, meta)` | `int` | Crea sesión como host. |
| `join_session(session_info)` | `int` | Une como cliente con SessionInfo. |
| `join_session_by_room_code(code)` | `int` | Une por código de sala. |
| `close_session()` | `void` | Cierra la sesión activa. |
| `get_current_session()` | `SessionInfo` | Sesión activa o `null`. |
| `get_room_code()` | `String` | Código de la sala activa. |
| `has_room()` | `bool` | ¿Hay sesión activa? |
| `is_in_session()` | `bool` | ¿En sesión? |
| `is_host()` | `bool` | ¿Soy host? |
| `is_client()` | `bool` | ¿Soy cliente? |
| `is_singleplayer()` | `bool` | ¿Solo un jugador? |
| `is_multiplayer()` | `bool` | ¿Más de un jugador? |
| `is_lan()` | `bool` | ¿Backend LAN activo? |

## Jugadores

| Método | Retorna | Descripción |
|--------|---------|-------------|
| `set_local_player_name(name)` | `void` | Nombre del jugador local. |
| `set_player_profile(name, meta, data)` | `void` | Perfil completo del jugador local. |
| `get_local_player_name()` | `String` | Nombre del jugador local. |
| `get_local_peer_id()` | `int` | ID de red del peer local. |
| `get_local_player()` | `PlayerInfo` | PlayerInfo del jugador local. |
| `get_player_info(peer_id)` | `PlayerInfo` | PlayerInfo de un peer. |
| `get_players()` | `Array[PlayerInfo]` | Todos los jugadores. |
| `get_remote_players()` | `Array[PlayerInfo]` | Solo jugadores remotos. |
| `get_host_player()` | `PlayerInfo` | PlayerInfo del host. |
| `get_client_players()` | `Array[PlayerInfo]` | Solo clientes. |
| `get_connected_peers()` | `Array[int]` | IDs de peers conectados. |
| `is_local_player_id(peer_id)` | `bool` | ¿Es el peer local? |
| `is_local_player_info(info)` | `bool` | ¿Es el PlayerInfo local? |
| `is_player_connected(peer_id)` | `bool` | ¿Está conectado? |
| `kick_player(peer_id, reason)` | `void` | Patear a un jugador (solo host). |
| `update_local_player_data(key, val)` | `void` | Actualiza datos locales. |
| `remove_local_player_data(key)` | `void` | Elimina dato local. |
| `set_player_data(peer, key, val)` | `bool` | Modifica datos de cualquier jugador. |
| `get_player_data(peer_id)` | `Dictionary` | Lee datos de un jugador. |
| `remove_player_data(peer, key)` | `bool` | Elimina dato de jugador. |

## Autoridad

| Método | Retorna | Descripción |
|--------|---------|-------------|
| `set_entity_authority(entity, peer)` | `void` | Asigna autoridad. |
| `get_entity_authority(entity)` | `int` | Retorna el peer con autoridad. |
| `is_entity_authority(entity)` | `bool` | ¿Tengo autoridad sobre esta entidad? |
| `request_authority(entity)` | `void` | Solicitar autoridad (TRANSFERABLE). |
| `transfer_authority(entity, peer)` | `void` | Transferir autoridad a otro peer. |
| `validate_authority_change(entity, peer)` | `bool` | ¿Es válido transferir? |

## Replicación de estado

| Método | Retorna | Descripción |
|--------|---------|-------------|
| `register_entity(node, props, mode, id)` | `void` | Registrar entidad en el replicador. |
| `unregister_entity(node)` | `void` | Desregistrar entidad. |
| `allocate_entity_network_id()` | `int` | Genera un ID de entidad de red único. |
| `set_global_state(key, value)` | `void` | Escribe en el estado global (solo host). |
| `get_global_state(key, default)` | `Variant` | Lee del estado global. |

## Carga de escena

| Método | Retorna | Descripción |
|--------|---------|-------------|
| `request_scene_load(scene_path)` | `void` | Host solicita carga de escena a todos. |
| `report_scene_ready()` | `void` | El peer local notifica que cargó la escena. |
| `replay_late_join_spawns_now(peer_id)` | `void` | Fuerza el replay de spawns para un peer. |
| `run_late_join_snapshot_only(peer_id)` | `void` | Envía solo el snapshot de mundo (sin spawns). |

## RPC

| Método | Retorna | Descripción |
|--------|---------|-------------|
| `send_rpc(peer, method, args, reliable)` | `void` | Envío a un peer. |
| `send_rpc_to_host(method, args, reliable)` | `void` | Envío al host. |
| `broadcast_rpc(method, args, reliable)` | `void` | Envío a todos. |
| `send_to_all(method, payload, reliable)` | `void` | Atajo de broadcast. |
| `send_to_host(method, payload, reliable)` | `void` | Atajo a host. |
| `send_to_player(peer, method, payload, reliable)` | `void` | Atajo a jugador. |
| `send_to_clients(method, payload, reliable)` | `void` | Atajo a todos los clientes. |
| `register_rpc(method, callable)` | `void` | Registrar handler. |
| `unregister_rpc(method)` | `void` | Desregistrar handler. |

## Optimización

| Método | Retorna | Descripción |
|--------|---------|-------------|
| `set_interest_area(entity, area)` | `void` | Define el área de interés (culling de red). |
| `get_network_stats()` | `Dictionary` | Estadísticas de la conexión. |

## Debug

| Método | Retorna | Descripción |
|--------|---------|-------------|
| `debug_mode(enabled)` | `void` | Activa/desactiva modo debug. |
| `enable_debug_overlay(enabled)` | `void` | Activa hooks de debug. |
| `get_debug_metrics()` | `Dictionary` | Métricas básicas: state, tick, peers, backend. |
| `dump_network_state()` | `Dictionary` | Volcado completo del estado de red. |
| `get_connection_state()` | `int` | Estado interno de la máquina de estados. |
| `get_feedback_logs(limit, min_level)` | `Array[Dictionary]` | Entradas del log filtradas. |
| `get_logs(limit)` | `Array[Dictionary]` | Todas las entradas del log. |
| `get_logs_type(level_name, limit)` | `Array[Dictionary]` | Log filtrado por nivel. |
| `set_feedback_log_capacity(max)` | `void` | Límite de entradas en el log. |
| `clear_feedback_logs()` | `void` | Vacía el log. |

---

<!-- doc-shell:page slug="debug" -->

# Debug y Diagnóstico

LinkUx incluye un completo sistema de diagnóstico que puedes usar tanto durante el desarrollo como para paneles in-game.

## Activar modo debug

```gdscript
# En la configuración
config.debug_enabled = true
config.log_level = 4  # DEBUG

# O en tiempo de ejecución
LinkUx.debug_mode(true)   # Activa debug y sube el log a DEBUG
LinkUx.debug_mode(false)  # Desactiva y restaura el log_level de config
```

---

## Métricas básicas

```gdscript
var metrics := LinkUx.get_debug_metrics()
# {
#   "state":   "RUNNING",    ← Estado de la máquina interna
#   "tick":    247,          ← Tick de red actual
#   "peers":   3,            ← Peers conectados
#   "backend": "LAN"         ← Backend activo
# }
```

---

## Volcado completo del estado

```gdscript
var estado := LinkUx.dump_network_state()
# {
#   "state_machine": "RUNNING",
#   "backend":       "LAN",
#   "is_host":       true,
#   "local_peer_id": 1,
#   "connected_peers": [2, 3],
#   "players":       [1, 2, 3],
#   "session":       { session_id, room_code, ... }
# }
print(JSON.stringify(estado, "  "))
```

---

## Sistema de logs

LinkUx mantiene un feed interno de logs accesible con:

```gdscript
# Últimas 50 entradas de cualquier nivel
var logs := LinkUx.get_logs(50)

# Solo errores (limit 0 = todos)
var errores := LinkUx.get_logs_type("ERROR")

# Entradas nivel INFO o superior
var info_logs := LinkUx.get_feedback_logs(0, DebugLogger.LogLevel.INFO)
```

Cada entrada del log es un `Dictionary`:

```gdscript
{
    "level":          3,           # int — LogLevel
    "level_name":     "INFO",      # String
    "context":        "Core",      # Sistema que generó el log
    "message":        "Initialized with backend: LAN",
    "formatted":      "[INFO][Core] Initialized with backend: LAN",
    "timestamp_msec": 12430        # Time.get_ticks_msec()
}
```

### Escuchar logs en tiempo real

```gdscript
func _ready() -> void:
    LinkUx.feedback_log_added.connect(_on_log)

func _on_log(entry: Dictionary) -> void:
    if entry["level"] >= 3:  # INFO o superior
        $DebugLabel.text += "\n" + entry["formatted"]
```

### Configurar capacidad

```gdscript
# Guardar solo las últimas 200 entradas (por defecto 500)
LinkUx.set_feedback_log_capacity(200)

# Limpiar el log
LinkUx.clear_feedback_logs()
```

---

## Estadísticas de red

```gdscript
var stats := LinkUx.get_network_stats()
# Contiene datos del DisconnectHandler:
# heartbeats enviados/recibidos, timeouts, etc.
```

---

## Panel de debug in-game (ejemplo)

```gdscript
# debug_panel.gd
extends PanelContainer

func _process(_delta: float) -> void:
    if not visible:
        return
    var m := LinkUx.get_debug_metrics()
    $Grid/State.text  = m.get("state", "—")
    $Grid/Tick.text   = str(m.get("tick", 0))
    $Grid/Peers.text  = str(m.get("peers", 0))
    $Grid/Backend.text = m.get("backend", "—")
    $Grid/PeerID.text = str(LinkUx.get_local_peer_id())
    $Grid/IsHost.text = str(LinkUx.is_host())
```

---

<!-- doc-shell:page slug="backend-lan" -->

# Backend LAN

El backend LAN es el único backend disponible actualmente en LinkUx. Está basado en **ENetMultiplayerPeer** de Godot y permite jugar en red local con conexión directa por IP y puerto.

## Cómo funciona

```
Host (ENet Server)
│
├── ENet ←→ Cliente 1
├── ENet ←→ Cliente 2
└── ENet ←→ Cliente 3

Topología estrella: los clientes no se conectan entre sí.
El host retransmite los paquetes de cada cliente al resto.
```

## Código de sala

Al crear una sesión LAN, LinkUx genera automáticamente un **código de sala alfanumérico de 8 caracteres** (p.ej. `"A3F7KQ2P"`). Los clientes usan este código para encontrar y unirse a la sala sin necesidad de saber la IP del host.

Internamente, el código codifica la IP y el puerto del servidor ENet. Al resolver el código, LinkUx conecta directamente al peer que actúa de host.

```gdscript
// Después de crear la sesión, mostrar el código
func _on_session_created(info: SessionInfo) -> void:
    $CodeLabel.text = "Código de sala: " + info.room_code
    // También accesible como:
    // LinkUx.get_room_code()
```

## Port stride — Múltiples hosts en la misma máquina

Para pruebas en la misma PC, `LanBackendConfig.lan_port_stride` permite crear varios servidores en la misma máquina. Si el puerto base (`7777`) ya está ocupado, LinkUx prueba `7779`, `7781`, etc., hasta `max_lan_host_attempts` intentos.

```gdscript
config.lan = LanBackendConfig.new()
config.lan.default_port        = 7777
config.lan.lan_port_stride     = 2
config.lan.max_lan_host_attempts = 8
// Prueba: 7777, 7779, 7781, 7783, 7785, 7787, 7789, 7791
```

## Timeout de conexión

Al unirse por código, si no se puede establecer la conexión ENet en `connection_timeout` segundos, LinkUx cierra el intento y emite `connection_failed`:

```gdscript
config.lan.connection_timeout = 3.0  // segundos
```

## Nota sobre `multiplayer_poll`

LinkUx usa paquetes binarios personalizados a través de ENet, distintos del sistema RPC de Godot. Por eso, al activar el backend LAN, LinkUx **desactiva automáticamente** `SceneTree.multiplayer_poll` para evitar que Godot intente parsear los paquetes de LinkUx como RPCs del motor.

Esto es transparente — no necesitas hacerlo manualmente.

## Activar el backend LAN

```gdscript
LinkUx.set_backend(NetworkEnums.BackendType.LAN)
// — o en la config inicial —
config.default_backend = NetworkEnums.BackendType.LAN
```

## Verificar el backend activo

```gdscript
if LinkUx.is_lan():
    print("Usando backend LAN")

// O con el nombre:
print(LinkUx.get_backend_name())  // "LAN"
```

---

<!-- doc-shell:page slug="backends-proximos" -->

# Backends Próximos

LinkUx está diseñado desde cero para soportar múltiples backends. La clase base `NetworkBackend` define la interfaz que cualquier backend debe implementar, y el resto del sistema (API, subsistemas, nodos) es completamente agnóstico al transporte.

## Estado actual

| Backend | Estado | Notas |
|---------|--------|-------|
| **LAN (ENet)** | ✅ Disponible | Red local, conexión directa. |
| **Online — Relay** | 🔜 Planificado | Servidor de relay para juego en internet sin abrir puertos. |
| **Online — EOS / Servicios** | 🔜 Planificado | Integración con servicios de matchmaking en la nube. |

## Cambiar de backend sin tocar el código de juego

Esta es la promesa central de LinkUx. Cuando los backends Online estén disponibles, el único cambio necesario en tu juego será:

```gdscript
# Hoy (LAN):
LinkUx.set_backend(NetworkEnums.BackendType.LAN)

# Mañana (Online):
LinkUx.set_backend(NetworkEnums.BackendType.ONLINE_RELAY)  # próximamente
```

**El resto de tu código — señales, RPCs, Spawner, Synchronizer — no cambia.**

## Cómo se integra un backend

Cada backend es un script que hereda de `NetworkBackend` e implementa métodos como `_backend_create_server()`, `_backend_connect()`, `_backend_kick_peer()`, etc. LinkUx detecta las capacidades del backend mediante `BackendCapabilityChecker` y advierte si falta alguna.

Para añadir soporte a un nuevo backend en el futuro, solo hay que:
1. Crear el script del backend bajo `addons/linkux/backends/tu_backend/`.
2. Añadir el caso correspondiente en el enum `BackendType`.
3. Registrar el backend en `set_backend()` de `linkux.gd`.

## Mantente al día

Las actualizaciones de LinkUx con nuevos backends se anunciarán en el repositorio oficial del addon.

---

<!-- doc-shell:page slug="ejemplo-completo" -->

# Ejemplo Completo

Un juego multijugador mínimo pero completamente funcional usando LinkUx. Incluye menú, carga de escena sincronizada, spawn de jugadores y movimiento básico en primera persona.

## Estructura del proyecto

```
proyecto/
├── autoloads/
│   └── GLOBAL.gd          ← Autoload: inicializa LinkUx
├── scenes/
│   ├── menu.tscn           ← Menú principal
│   ├── level.tscn          ← Nivel multijugador
│   └── player.tscn         ← Prefab del jugador
└── scripts/
    ├── menu.gd
    ├── level.gd
    └── player.gd
```

---

## GLOBAL.gd — Autoload de juego

```gdscript
# autoloads/GLOBAL.gd
extends Node

func _ready() -> void:
    await get_tree().process_frame
    _init_linkux()
    LinkUx.scene_load_requested.connect(_on_scene_load_requested)
    LinkUx.session_closed.connect(_on_session_closed)

func _init_linkux() -> void:
    if LinkUx.get_config() != null:
        return
    var config := LinkUxConfig.new()
    config.network = NetworkConfig.new()
    config.network.tick_rate = 30
    config.log_level = 3
    LinkUx.initialize(config)

func _on_scene_load_requested(scene_path: String) -> void:
    get_tree().change_scene_to_file(scene_path)

func _on_session_closed() -> void:
    get_tree().change_scene_to_file("res://scenes/menu.tscn")
```

---

## menu.gd — Menú principal

```gdscript
# scripts/menu.gd
extends Control

func _ready() -> void:
    LinkUx.prepare_for_new_session()
    LinkUx.session_started.connect(_on_session_started)
    LinkUx.connection_failed.connect(_on_connection_failed)

func _on_host_btn_pressed() -> void:
    var nickname: String = $NicknameInput.text.strip_edges()
    if nickname.is_empty():
        return
    LinkUx.set_local_player_name(nickname)
    LinkUx.set_backend(NetworkEnums.BackendType.LAN)
    LinkUx.create_session("Sala de " + nickname, 4)

func _on_join_btn_pressed() -> void:
    var nickname: String = $NicknameInput.text.strip_edges()
    var code: String     = $CodeInput.text.strip_edges().to_upper()
    if nickname.is_empty() or code.is_empty():
        return
    LinkUx.set_local_player_name(nickname)
    LinkUx.set_backend(NetworkEnums.BackendType.LAN)
    var err := LinkUx.join_session_by_room_code(code)
    if err != NetworkEnums.ErrorCode.SUCCESS:
        $StatusLabel.text = "Sala no encontrada (código inválido)"

func _on_session_started() -> void:
    $CodeLabel.text = "Código: " + LinkUx.get_room_code()
    if LinkUx.is_host():
        LinkUx.request_scene_load("res://scenes/level.tscn")

func _on_connection_failed(error: String) -> void:
    $StatusLabel.text = "Error: " + error
```

---

## level.gd — Nivel de juego

```gdscript
# scripts/level.gd
extends Node3D

@onready var spawner: LinkUxSpawner = $PlayerSpawner

func _ready() -> void:
    LinkUx.player_joined.connect(_on_player_joined)
    LinkUx.player_left_processed.connect(_on_player_left)

    # Spawnear jugador local
    _spawn_player(LinkUx.get_local_peer_id())

    # Notificar que este peer terminó de cargar
    LinkUx.report_scene_ready()

func _on_player_joined(info: PlayerInfo) -> void:
    if info.peer_id == LinkUx.get_local_peer_id():
        return  # Ya spawneado en _ready
    _spawn_player(info.peer_id)

func _on_player_left(_info: PlayerInfo, _reason: int) -> void:
    pass  # LinkUxSpawner limpia automáticamente

func _spawn_player(peer_id: int) -> void:
    var pos := Vector3(randf_range(-3.0, 3.0), 1.0, randf_range(-3.0, 3.0))
    var nickname := "?"
    var p := LinkUx.get_player_info(peer_id)
    if p:
        nickname = p.display_name

    spawner.spawn(0, {
        "player_peer_id": peer_id,
        "player_nickname": nickname,
        "global_position": pos,
    }, peer_id)

func _unhandled_key_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel"):
        LinkUx.close_session()
```

---

## player.gd — Personaje jugador

```gdscript
# scripts/player.gd
extends CharacterBody3D

@export var player_peer_id: int = 0
@export var player_nickname: String = ""

const SPEED := 5.0
const MOUSE_SENSITIVITY := 0.002

func _ready() -> void:
    if not LinkUx.is_local_player_id(player_peer_id):
        set_process_unhandled_input(false)
        return
    # Solo para el jugador local
    $Camera3D.current = true
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
        $Camera3D.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
        $Camera3D.rotation.x = clamp($Camera3D.rotation.x, -1.4, 1.4)
    if event.is_action_pressed("ui_cancel"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(_delta: float) -> void:
    if not LinkUx.is_local_player_id(player_peer_id):
        return
    var dir := Vector3(
        Input.get_axis("move_left", "move_right"),
        0,
        Input.get_axis("move_forward", "move_back")
    )
    dir = dir.rotated(Vector3.UP, rotation.y)
    velocity = dir.normalized() * SPEED
    if not is_on_floor():
        velocity.y -= 9.8 * _delta
    move_and_slide()
```

---

## player.tscn — Scene tree del jugador

```
CharacterBody3D  (player.gd)
├── CollisionShape3D
├── MeshInstance3D
├── Camera3D
└── LinkUxSynchronizer
    sync_properties:      ["position", "rotation"]
    interpolate:          true
    remote_smoothing_hz:  24.0
```

---

## level.tscn — Scene tree del nivel

```
Node3D  (level.gd)
├── WorldEnvironment
├── DirectionalLight3D
├── MeshInstance3D (floor)
├── PlayerSpawner  (LinkUxSpawner)
│   spawn_path: Players
│   spawnable_scenes: [player.tscn]
└── Players  (Node3D)
```

---

## Flujo completo

```
1. Jugador A → create_session()  →  [session_started]
   └── request_scene_load("level.tscn")
   └── [scene_load_requested] → GLOBAL carga la escena

2. Jugador B → join_session_by_room_code(código)  →  [session_started]
   └── GLOBAL recibe [scene_load_requested] → carga la escena

3. Ambos llaman report_scene_ready()
   └── [scene_all_ready] → tick loop inicia

4. Cada level.gd spawna su jugador local via LinkUxSpawner
   └── El Spawner replica el spawn a todos los peers

5. LinkUxSynchronizer envía position/rotation cada tick
   └── Los peers remotos reciben y aplican con interpolación

6. Al salir → close_session() → [session_closed] → menú
```
