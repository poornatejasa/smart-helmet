# Smart Helmet BLE Protocol

The ESP32 is a single-connection NimBLE peripheral. It advertises the telemetry
and OTA services, requires an encrypted, bonded connection for every read and
write, and keeps the GATT database fixed across firmware updates.

All multi-byte fields use little-endian byte order. Version 1 reserves unused
fields for future extension; do not change existing UUIDs or packet layouts
after a companion application is released.

## Services

| Service | UUID | Characteristics | Purpose |
|---|---:|---|---|
| Telemetry | `0xFFF0` | Data `0xFFF1`, Alert `0xFFF2` | Sensor state and immediate alerts |
| Configuration | `0xFFF3` | Config `0xFFF4`, Result `0xFFF5` | Read/change persistent settings |
| Firmware OTA | `0xFFF6` | Control `0xFFF7`, Data `0xFFF8`, Status `0xFFF9` | Verified ESP32 firmware update |
| File transfer | `0xFFFA` | Control `0xFFFB`, Data `0xFFFC`, Status `0xFFFD` | One verified arbitrary staged file |

`Data`, `Alert`, `Result`, and `Status` use notifications. The client should
enable notifications before issuing a command where it needs an asynchronous
result.

## Telemetry and alerts

Telemetry (`0xFFF1`) is readable and notifies at the configured interval:

```text
version:u8 | flags:u8 | sequence:u16 | timestamp_ms:u32 |
payload_length:u8 | payload:0..64 bytes
```

The payload is intentionally application-defined. The UART integration owns the
mapping from STM32 messages to the flags and payload, which lets sensor fields
evolve without changing the BLE transport.

Alerts (`0xFFF2`) notify immediately:

```text
code:u8 | severity:u8 | sequence:u16 | timestamp_ms:u32 |
payload_length:u8 | payload:0..32 bytes
```

Suggested severity values are `1=info`, `2=warning`, and `3=critical`.

## Configuration

Read `0xFFF4` to obtain:

```text
protocol_version:u8 | telemetry_interval_ms:u16 | alerts_enabled:u8 |
device_name_length:u8 | device_name:ASCII
```

Write commands to `0xFFF4`; command processing occurs outside the NimBLE
callback and the result is notified on `0xFFF5` as `0x80 | command | result`,
where `0` means success.

| Command | Request |
|---:|---|
| `0x01` | `command | telemetry_interval_ms:u16` (100–60000 ms) |
| `0x02` | `command | alerts_enabled:u8` (`0` or `1`) |
| `0x03` | `command | device_name:1..20 printable bytes` |
| `0x04` | `command` (restore telemetry defaults) |

Device names always end in `Helmet`. Rename normalizes an existing suffix or
adds ` Helmet`; the complete name stays within 20 ASCII bytes (13 for a custom
prefix). On startup, legacy saved names are normalized; long legacy prefixes
are shortened to fit. Reset uses `Smart Helmet`. The companion only lists
advertised names ending in `Helmet` (case-insensitive) and still verifies the
GATT service on connection. The suffix is a discovery filter, not authentication.

## OTA firmware transfer

The client computes a SHA-256 digest of the exact firmware image before the
transfer. Write `START` to `0xFFF7`, wait until the status reports
`RECEIVING`, then stream chunks to `0xFFF8` using Write Without Response. A
chunk must never exceed the negotiated ATT payload size (`MTU - 3`) or 240
bytes, whichever is smaller. Read or subscribe to `0xFFF9` for progress.

| Command | Value |
|---:|---|
| `0x01 START` | `command | image_size:u32 | sha256:32 bytes` |
| `0x02 FINISH` | `command` after every data packet has been accepted |
| `0x03 ABORT` | `command` |
| `0x04 REBOOT` | `command`, only after `COMPLETED` |

Status format:

```text
state:u8 | progress_percent:u8 | bytes_received:u32 | total_size:u32
```

States are `0=IDLE`, `1=RECEIVING`, `2=VERIFYING`, `3=COMPLETED`, and
`4=FAILED`. A completed OTA image becomes the boot target; it is activated only
after the explicit reboot command.

## Generic file transfer

This service follows the OTA sequence but writes an application-defined file to
the dedicated `storage` partition rather than an OTA slot. It supports one
staged file at a time. The receiving application must define each `file_type`.

| Command | Value |
|---:|---|
| `0x01 START` | `command | file_type:u8 | file_size:u32 | sha256:32 bytes` |
| `0x02 FINISH` | `command` |
| `0x03 ABORT` | `command` |

The status format and state values are identical to OTA. File data uses chunks
no larger than the negotiated ATT payload size or 240 bytes, whichever is
smaller, on `0xFFFC`.

## Safety and integration notes

- GATT callbacks only validate/copy a request into a queue. NVS and flash
  writes happen in the main firmware task.
- A disconnect aborts an active OTA or file-transfer session.
- The default partition table targets a 4 MB module. Recalculate it before
  selecting a board with a different flash size.
- Future UART code should call `helmet_ble_publish_telemetry()` and
  `helmet_ble_publish_alert()`; it should not access NimBLE APIs directly.
