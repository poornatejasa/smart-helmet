# Smart Helmet app

One Flutter codebase for the Helmet companion app. Android and Windows are the
current development targets; the iOS project is retained for later testing on
Apple hardware.

## What works in the app

- List nearby devices whose names end in Helmet, verify the Smart Helmet BLE
  service on connection, and retry a dropped connection.
- View a single live summary with packet count, alert count and update interval.
- Open the safety dashboard for sobriety, drowsiness and impact cards, live
  update status, and recent alerts.
- Read the update interval and change alerts, advertised name, and reset.
  Names automatically end in Helmet; the custom prefix allows 13 ASCII
  characters. There is no update interval slider in Settings.
- Transfer a firmware image from Settings with SHA-256 verification, progress,
  abort, and a separate action before rebooting into new firmware.
- Navigate with three tabs: Overview, Devices, Settings. The system back action
  closes safety details or returns to Overview; from Overview it exits the app.

The BLE UUIDs and packet formats match [`../docs/ble-protocol.md`](../docs/ble-protocol.md).
The UI shows update counts and alert severity without raw protocol details.
The STM32-to-ESP32 sensor data schema has not been defined. Sobriety,
drowsiness, and impact cards therefore remain neutral rather than green until
real sensor values and safe thresholds are defined. Each card can then turn
green for an in-range value or red for its own out-of-range value. The app does
not yet send emergency messages or upload location to a
server; that requires a separate, agreed design and permissions.

## UI conventions

Use the shared `AppText` styles and control themes in `lib/main.dart` rather
than per-screen font sizes. Page titles are 22, section headings 15, labels 14,
body and button text 13, captions 12, and sensor values 16 logical pixels.
Cards use 16-pixel padding; internal spacing uses 4, 8, 12, or 16 pixels.
System text scaling remains enabled, and device actions stack on narrow layouts.

## Run locally

Device names ignore surrounding/repeated whitespace and always end in `Helmet`.
Saving a name keeps the BLE connection open. Devices > Refresh reads the current
name while connected, or starts a fresh scan while disconnected. The new name
is advertised on the next normal disconnect; there is no need to unpair.

The current ESP32-C6 board uses one WS2812 on GPIO8: red when disconnected,
blue when connected. This indicator requires flashing the updated firmware;
the ESP-IDF component manager resolves `espressif/led_strip` during your build.

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
