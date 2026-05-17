# Godot 4.6 — Multiplayer API Reference

> Context file for AI assistance. Covers `MultiplayerAPI`, `MultiplayerAPIExtension`, `SceneMultiplayer`, and `PacketPeer`.

---

## Class Hierarchy Overview

```
RefCounted
└── MultiplayerAPI                  ← Abstract base interface
    ├── MultiplayerAPIExtension     ← Override/extend the API via GDScript/GDExtension
    └── SceneMultiplayer            ← Default implementation (used by SceneTree)

RefCounted
└── PacketPeer                      ← Low-level packet send/receive base
    ├── MultiplayerPeer             ← (peer transport layer, not covered here)
    ├── PacketPeerUDP
    ├── PacketPeerDTLS
    ├── PacketPeerStream
    ├── ENetPacketPeer
    ├── WebRTCDataChannel
    └── WebSocketPeer
```

**Access point:** Every node has a `multiplayer` property returning the `MultiplayerAPI` instance for its branch.

```gdscript
var api: MultiplayerAPI = multiplayer           # current branch's API
var api: MultiplayerAPI = get_tree().get_multiplayer(NodePath("/root/Game"))
```

---

## 1. MultiplayerAPI

**Inherits:** `RefCounted`
**Ref:** `https://docs.godotengine.org/en/stable/classes/class_multiplayerapi.html`

Base class for all high-level multiplayer implementations. `SceneTree` holds a reference to an instance of this and uses it to provide RPC capabilities across the scene. Specific branches can run their own instance via `SceneTree.set_multiplayer()`.

### Properties

| Property | Type | Description |
|---|---|---|
| `multiplayer_peer` | `MultiplayerPeer` | The transport layer peer. Setting this enables networking. Server mode is set when the peer is a listening server; client mode otherwise. All child nodes inherit the network mode by default. |

### Static Methods

| Method | Returns | Description |
|---|---|---|
| `create_default_interface()` | `MultiplayerAPI` | Returns a new instance of the default implementation (usually `SceneMultiplayer`). |
| `get_default_interface()` | `StringName` | Returns the name of the default implementation class (usually `"SceneMultiplayer"`). |
| `set_default_interface(interface_name)` | `void` | Sets which class is used as the default implementation (useful for modules/extensions). |

### Instance Methods

| Method | Returns | Description |
|---|---|---|
| `has_multiplayer_peer()` | `bool` | Returns `true` if a `multiplayer_peer` is assigned. |
| `is_server()` | `bool` | Returns `true` if the peer is valid and in server mode. |
| `get_unique_id()` | `int` | Returns the local peer's unique ID. |
| `get_peers()` | `PackedInt32Array` | Returns IDs of all currently connected peers. |
| `get_remote_sender_id()` | `int` | Returns the peer ID of the sender during an active RPC. Returns `0` if called outside an RPC. |
| `poll()` | `Error` | Manually polls the API. Only needed if `SceneTree.multiplayer_poll` is `false`. RPCs are executed in the same context as this call. |
| `rpc(peer, object, method, arguments)` | `Error` | Sends an RPC to `peer`. Prefer `Node.rpc()` / `Node.rpc_id()` for speed; this is mainly useful with extensions. |
| `object_configuration_add(object, configuration)` | `Error` | Notifies the API of a new configuration for an object (used internally by `SceneTree` to set the root path). |
| `object_configuration_remove(object, configuration)` | `Error` | Removes a configuration from the API for an object. |

### Signals

| Signal | Description |
|---|---|
| `connected_to_server()` | Emitted on clients when the peer successfully connects to a server. |
| `connection_failed()` | Emitted on clients when connection to a server fails. |
| `server_disconnected()` | Emitted on clients when disconnected from the server. |
| `peer_connected(id: int)` | Emitted when a new peer connects. Clients also receive this for the server (`id = 1`). |
| `peer_disconnected(id: int)` | Emitted when a peer disconnects. |

### Enum: RPCMode

| Constant | Value | Description |
|---|---|---|
| `RPC_MODE_DISABLED` | `0` | Default. Method is not callable via RPC. |
| `RPC_MODE_ANY_PEER` | `1` | Callable by any remote peer. Analogous to `@rpc("any_peer")`. |
| `RPC_MODE_AUTHORITY` | `2` | Callable only by the current multiplayer authority (server by default). Analogous to `@rpc("authority")`. |

### Key Notes

- Peer ID `1` is always the server.
- `get_remote_sender_id()` returns `0` if called outside an RPC, or after an `await` (the sender ID may be lost).
- The high-level multiplayer protocol is a Godot implementation detail and is not intended for use with non-Godot servers.
- On Android exports, enable the `INTERNET` permission.

---

## 2. MultiplayerAPIExtension

**Inherits:** `MultiplayerAPI` → `RefCounted`
**Ref:** `https://docs.godotengine.org/en/4.6/classes/class_multiplayerapiextension.html`

Allows replacing or augmenting the default multiplayer implementation via GDScript, C#, or GDExtension. Extend this class and override its virtual methods to provide custom behavior. Set it as the active API with `SceneTree.set_multiplayer()` or `MultiplayerAPI.set_default_interface()`.

### Virtual Methods to Override

| Virtual Method | Returns | Purpose |
|---|---|---|
| `_poll()` | `Error` | Called each frame to process incoming data. |
| `_set_multiplayer_peer(peer)` | `void` | Handle assignment of the transport peer. |
| `_get_multiplayer_peer()` | `MultiplayerPeer` | Return the currently assigned peer. |
| `_get_unique_id()` | `int` | Return this peer's unique ID. |
| `_get_peer_ids()` | `PackedInt32Array` | Return all connected peer IDs. |
| `_get_remote_sender_id()` | `int` | Return the sender ID during an active RPC. |
| `_rpc(peer_id, object, method, args)` | `Error` | Implement the actual RPC dispatch logic. |
| `_object_configuration_add(object, config)` | `Error` | Handle new configuration for an object. |
| `_object_configuration_remove(object, config)` | `Error` | Handle removal of a configuration. |

### Usage Pattern

```gdscript
class_name MyMultiplayerAPI extends MultiplayerAPIExtension

func _poll() -> Error:
    # Custom polling logic
    return OK

func _rpc(peer_id: int, object: Object, method: StringName, args: Array) -> Error:
    # Custom RPC dispatch
    return OK

# Activate on the tree or a branch:
SceneTree.set_multiplayer(MyMultiplayerAPI.new(), NodePath("/root/Game"))
# Or set globally before engine starts:
MultiplayerAPI.set_default_interface("MyMultiplayerAPI")
```

---

## 3. SceneMultiplayer

**Inherits:** `MultiplayerAPIExtension` → `MultiplayerAPI` → `RefCounted`
**Ref:** `https://docs.godotengine.org/en/stable/classes/class_scenemultiplayer.html`

The **default** implementation used by `SceneTree`. Supports:
- RPCs via `Node.rpc()` and `Node.rpc_id()` (requires the target object to be a `Node`).
- Scene replication via `MultiplayerSpawner` and `MultiplayerSynchronizer`.
- Optional peer authentication flow.
- Raw byte transmission via `send_bytes()`.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `root_path` | `NodePath` | — | Root used for RPC/replication path resolution. Enables multiple independent multiplayer sessions in one scene. |
| `refuse_new_connections` | `bool` | `false` | When `true`, the peer rejects incoming connections. |
| `allow_object_decoding` | `bool` | `false` | Allows encoding/decoding `Object` types in RPCs. **Warning:** Deserialized objects can execute arbitrary code; never enable with untrusted sources. |
| `server_relay` | `bool` | `true` | When enabled, the server notifies clients of other peers and relays packets between them. Disabling this hides peers from each other. Changing at runtime with connected peers may cause unexpected behavior. |
| `auth_callback` | `Callable` | `Callable()` | Called when authentication data arrives via `send_auth()`. If empty, peers are accepted immediately on connect. |
| `auth_timeout` | `float` | — | Max seconds a peer can stay in the authenticating state. `0.0` disables the timeout. |
| `max_sync_packet_size` | `int` | — | Max size of each `MultiplayerSynchronizer` sync packet. Larger = more chance of full updates per frame, but higher packet loss risk. |
| `max_delta_packet_size` | `int` | — | Max size of each `MultiplayerSynchronizer` delta packet. Larger = more chance of full updates per frame, but higher congestion risk. |

### Methods

| Method | Returns | Description |
|---|---|---|
| `clear()` | `void` | Resets all network state. Use with caution. |
| `send_bytes(bytes, id=0, mode=TRANSFER_MODE_RELIABLE, channel=0)` | `Error` | Sends raw bytes to a peer (`id=0` = broadcast). |
| `send_auth(id, data)` | `Error` | Sends authentication data to an authenticating peer. |
| `complete_auth(id)` | `Error` | Marks authentication as done for peer `id`. `peer_connected` is emitted once the remote side also completes. |
| `disconnect_peer(id)` | `void` | Forcefully disconnects a peer by ID. |
| `get_authenticating_peers()` | `PackedInt32Array` | Returns IDs of peers currently in the authenticating state (not yet in `get_peers()`). |

### Signals

| Signal | Description |
|---|---|
| `peer_authenticating(id: int)` | Emitted when a peer connects and `auth_callback` is set. `peer_connected` is suppressed until `complete_auth()` is called. |
| `peer_authentication_failed(id: int)` | Emitted when an authenticating peer disconnects (timeout, network error, or `disconnect_peer()`). |
| `peer_packet(id: int, packet: PackedByteArray)` | Emitted when a raw packet is received via `send_bytes()`. |

### Authentication Flow

```
Peer connects
    │
    ▼
peer_authenticating(id) emitted        ← auth_callback set
    │
    ▼
Exchange data via send_auth() / auth_callback
    │
    ▼
complete_auth(id)                       ← both sides must complete
    │
    ▼
peer_connected(id) emitted              ← peer now fully accepted
```

If `auth_timeout > 0` and authentication is not completed in time → `peer_authentication_failed(id)`.

### Server Relay

When `server_relay = true` (default), the server:
- Notifies clients when other clients connect/disconnect.
- Relays packets between clients (clients can send to each other via the server).

Set `server_relay = false` for authoritative-server architectures where clients should not communicate peer-to-peer.

---

## 4. PacketPeer

**Inherits:** `RefCounted`
**Ref:** `https://docs.godotengine.org/en/stable/classes/class_packetpeer.html`

Abstract base class for all **packet-based** communication. Provides a unified API for sending and receiving data as either raw bytes or `Variant` values, without needing to handle low-level serialization or network byte ordering.

**Known subclasses:** `MultiplayerPeer`, `PacketPeerUDP`, `PacketPeerDTLS`, `PacketPeerStream`, `ENetPacketPeer`, `PacketPeerExtension`, `WebRTCDataChannel`, `WebSocketPeer`.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `encode_buffer_max_size` | `int` | `8388608` (8 MB) | Maximum buffer size for encoding a `Variant` via `put_var()`. If the encoded size exceeds this, `ERR_OUT_OF_MEMORY` is returned. The buffer grows automatically to the next power of two. |

### Methods

| Method | Returns | Description |
|---|---|---|
| `get_available_packet_count()` | `int` | Returns how many packets are waiting in the ring-buffer. |
| `get_packet()` | `PackedByteArray` | Retrieves and removes the next raw packet. |
| `get_packet_error()` | `Error` | Returns the error state of the last `get_packet()` or `get_var()` call. |
| `get_var(allow_objects: bool = false)` | `Variant` | Retrieves and deserializes the next packet as a `Variant`. Uses the same mechanism as `bytes_to_var()`. Set `allow_objects = true` only with trusted sources. |
| `put_packet(buffer: PackedByteArray)` | `Error` | Sends a raw byte packet. |
| `put_var(var: Variant, full_objects: bool = false)` | `Error` | Serializes a `Variant` and sends it as a packet. Uses the same mechanism as `var_to_bytes()`. |

### Usage Pattern

```gdscript
# Sending
peer.put_var({"action": "jump", "player_id": 3})
peer.put_packet("hello".to_utf8_buffer())

# Receiving (typically in _process or on signal)
while peer.get_available_packet_count() > 0:
    var data = peer.get_var()
    if peer.get_packet_error() != OK:
        push_error("Packet error")
        continue
    handle_data(data)
```

### Security Notes

- `get_var(allow_objects: true)` and `put_var(full_objects: true)` can serialize/deserialize `Object` instances, which may contain executable code. **Never use with untrusted data.**
- `put_var()` allocates stack memory; ensure `encode_buffer_max_size` is appropriate for large payloads.

---

## Quick Reference: Common Patterns

### Setting Up a Server (ENet example)

```gdscript
var peer = ENetMultiplayerPeer.new()
peer.create_server(PORT, MAX_CLIENTS)
multiplayer.multiplayer_peer = peer
multiplayer.peer_connected.connect(_on_peer_connected)
multiplayer.peer_disconnected.connect(_on_peer_disconnected)
```

### Connecting as a Client

```gdscript
var peer = ENetMultiplayerPeer.new()
peer.create_client(SERVER_IP, PORT)
multiplayer.multiplayer_peer = peer
multiplayer.connected_to_server.connect(_on_connected)
multiplayer.connection_failed.connect(_on_failed)
```

### RPC Declaration and Call

```gdscript
@rpc("any_peer", "call_local", "reliable")
func sync_position(pos: Vector2) -> void:
    position = pos

# Call on all peers including self:
sync_position.rpc(position)

# Call on specific peer:
sync_position.rpc_id(peer_id, position)
```

### Running Client + Server in the Same Scene

```gdscript
# Server branch
var server_api = SceneMultiplayer.new()
server_api.root_path = NodePath("/root/ServerGame")
get_tree().set_multiplayer(server_api, NodePath("/root/ServerGame"))

# Client branch
var client_api = SceneMultiplayer.new()
client_api.root_path = NodePath("/root/ClientGame")
get_tree().set_multiplayer(client_api, NodePath("/root/ClientGame"))
```

### Sending Raw Bytes

```gdscript
# Via SceneMultiplayer
multiplayer.peer_packet.connect(_on_packet)
multiplayer.send_bytes("ping".to_utf8_buffer(), target_peer_id)

func _on_packet(sender_id: int, packet: PackedByteArray) -> void:
    print(packet.get_string_from_utf8())
```

---

## Peer ID Conventions

| ID | Meaning |
|---|---|
| `1` | Always the server |
| `0` | Broadcast (all peers) |
| `< 0` | Special targeting (see `MultiplayerPeer.set_target_peer`) |
| Any other positive `int` | Unique client peer ID |
