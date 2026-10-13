# Smart Helmet ESP32 Firmware

This folder is the ESP-IDF project root. Open `firmware/esp32-mcu/` in the
ESP-IDF extension; its generated `build/` directory and future board-specific
`idf-env/sdkconfig` stay here rather than at repository root.

## Layout

- `components/ble/` — NimBLE transport plus telemetry, alert, configuration,
  OTA, and generic file-transfer GATT services.
- `components/config/` — persisted, validated user configuration.
- `components/ota/` — firmware image staging and SHA-256 validation.
- `components/storage/` — generic staged-file storage in the `storage` partition.
- `idf-env/` — tracked ESP-IDF defaults and partition layout.
- `main/` — application entry point and component manifest.

The verified target is ESP32-C6 with 8 MB flash. The generated
`idf-env/sdkconfig` is tracked with this project; do not copy a configuration
generated for another ESP32 variant or flash capacity.

See [`../../docs/ble-protocol.md`](../../docs/ble-protocol.md) for the BLE
service and packet definitions.
