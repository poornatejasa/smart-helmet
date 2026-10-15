# Smart Helmet app

One Flutter codebase for the Helmet companion app. Android and Windows are the
current development targets; the iOS project is retained for later testing on
Apple hardware.

## What works in the app

- Scan for the Smart Helmet BLE service, connect, and retry a dropped connection.
- View the latest telemetry packet and live alert history from the ESP32-C6.
- Read and change the Helmet's BLE settings: update interval, alerts on/off,
  advertised name, and reset.
- Transfer a firmware image or file with SHA-256 verification, progress, abort,
  and a separate confirmation before rebooting into new firmware.
- Navigate with the Android/Windows back action or the in-app back arrow. Back
  returns to the previous app screen; on the root screen it does nothing.

The BLE UUIDs and packet formats match [`../docs/ble-protocol.md`](../docs/ble-protocol.md).
Telemetry payloads and alert codes are currently shown as raw values because
the STM32-to-ESP32 sensor data schema has not been defined. Sobriety,
drowsiness, and crash cards therefore do **not** infer a safe state from missing
data. The app does not yet send emergency messages or upload location to a
server; that requires a separate, agreed design and permissions.

## Run locally

Install Flutter, Android tooling for Android, or Visual Studio with the
Desktop development with C++ workload for Windows. From this directory:

```powershell
flutter pub get
flutter devices
flutter run -d windows
```

Choose an Android device ID from `flutter devices` to run on a phone instead.
For iOS, use a Mac with Xcode when that phase begins. BLE must be enabled and
the phone/PC must grant Bluetooth permissions. Connect inside the app, not in
the OS Bluetooth settings: the Helmet exposes a custom BLE GATT service rather
than a standard audio or serial profile.

For firmware updates, select a compatible signed-off ESP32-C6 application
image within the Helmet's OTA partition limit (1.25 MiB), then verify device
behavior after reboot. Do not use a bootloader or partition-table binary.
