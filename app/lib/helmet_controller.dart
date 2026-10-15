import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helmet_protocol.dart';

enum HelmetLinkState {
  disconnected,
  scanning,
  connecting,
  connected,
  reconnecting,
}

enum TransferKind { firmware, file }

class HelmetController extends ChangeNotifier {
  HelmetController() {
    _scanSubscription = UniversalBle.scanStream.listen(_onScanResult);
    _availabilitySubscription = UniversalBle.availabilityStream.listen((state) {
      bluetoothAvailable = state == AvailabilityState.poweredOn;
      notifyListeners();
    });
  }

  final Map<String, BleDevice> _seenDevices = {};
  final List<HelmetAlert> alerts = [];
  StreamSubscription<BleDevice>? _scanSubscription;
  StreamSubscription<AvailabilityState>? _availabilitySubscription;
  StreamSubscription<bool>? _connectionSubscription;
  final List<StreamSubscription<Uint8List>> _characteristicSubscriptions = [];
  Timer? _scanTimer;
  Timer? _reconnectTimer;

  BleDevice? _device;
  BleDevice? _wantedDevice;
  BleCharacteristic? _telemetryChar;
  BleCharacteristic? _alertChar;
  BleCharacteristic? _configChar;
  BleCharacteristic? _configResultChar;
  BleCharacteristic? _otaControlChar;
  BleCharacteristic? _otaDataChar;
  BleCharacteristic? _otaStatusChar;
  BleCharacteristic? _fileControlChar;
  BleCharacteristic? _fileDataChar;
  BleCharacteristic? _fileStatusChar;
  Completer<int>? _configResult;
  int? _pendingConfigCommand;
  int _session = 0;
  bool _connecting = false;
  bool _disposed = false;
  bool _abortTransfer = false;

  HelmetLinkState linkState = HelmetLinkState.disconnected;
  bool bluetoothAvailable = true;
  String? message;
  HelmetTelemetry? telemetry;
  int packetsReceived = 0;
  HelmetConfig? config;
  HelmetTransferStatus? otaStatus;
  HelmetTransferStatus? fileStatus;
  TransferKind? activeTransfer;
  String? transferFileName;
  int? negotiatedMtu;

  List<BleDevice> get devices {
    final result = _seenDevices.values.toList();
    result.sort((a, b) {
      final aHelmet = _looksLikeHelmet(a) ? 1 : 0;
      final bHelmet = _looksLikeHelmet(b) ? 1 : 0;
      if (aHelmet != bHelmet) return bHelmet.compareTo(aHelmet);
      return (b.rssi ?? -1000).compareTo(a.rssi ?? -1000);
    });
    return result;
  }

  bool get connected => linkState == HelmetLinkState.connected;
  bool get scanning => linkState == HelmetLinkState.scanning;
  bool get transferring => activeTransfer != null;
  String get deviceName =>
      config?.deviceName ?? _device?.name ?? 'Smart Helmet';
  String? get deviceId => _device?.deviceId;

  static bool _looksLikeHelmet(BleDevice device) =>
      (device.name?.toLowerCase().startsWith('smart-helmet') ?? false) ||
      device.services.any(
        (uuid) => HelmetUuid.matches(uuid, HelmetUuid.telemetryService),
      );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _setMessage(Object error) {
    message = error.toString().replaceFirst('Exception: ', '');
    _notify();
  }

  void clearMessage() {
    message = null;
    _notify();
  }

  void _onScanResult(BleDevice device) {
    if (device.name == null && device.services.isEmpty) return;
    _seenDevices[device.deviceId] = device;
    _notify();
  }

  Future<void> scan() async {
    if (_disposed || connected || _connecting) return;
    _reconnectTimer?.cancel();
    try {
      await UniversalBle.requestPermissions();
      final availability = await UniversalBle.getBluetoothAvailabilityState();
      bluetoothAvailable = availability == AvailabilityState.poweredOn;
      if (!bluetoothAvailable) {
        throw StateError('Turn on Bluetooth, then scan again.');
      }
      await stopScan();
      _seenDevices.clear();
      // No OS filter: renamed helmets are still discoverable.
      await UniversalBle.startScan();
      linkState = HelmetLinkState.scanning;
      _notify();
      _scanTimer = Timer(
        const Duration(seconds: 15),
        () => unawaited(stopScan()),
      );
      try {
        final systemDevices = await UniversalBle.getSystemDevices(
          withServices: [HelmetUuid.telemetryService],
        );
        for (final device in systemDevices) {
          _onScanResult(device);
        }
      } catch (_) {
        // Scanning still works when a platform cannot enumerate system devices.
      }
    } catch (error) {
      linkState = HelmetLinkState.disconnected;
      _setMessage(error);
    }
  }

  Future<void> stopScan() async {
    _scanTimer?.cancel();
    try {
      if (await UniversalBle.isScanning()) await UniversalBle.stopScan();
    } catch (_) {
      // Stop can race with an OS-driven scan timeout.
    }
    if (linkState == HelmetLinkState.scanning) {
      linkState = HelmetLinkState.disconnected;
      _notify();
    }
  }

  Future<void> connect(BleDevice device) async {
    _wantedDevice = device;
    _reconnectTimer?.cancel();
    await _connectWanted();
  }

  Future<void> _connectWanted() async {
    final candidate = _wantedDevice;
    if (_disposed || candidate == null || _connecting || connected) return;
    _connecting = true;
    final session = ++_session;
    linkState = HelmetLinkState.connecting;
    message = null;
    _notify();
    try {
      await stopScan();
      await candidate.connect(
        platformConfig: ConnectionPlatformConfig(
          android: AndroidConnectionOptions(closeGattOnDetach: true),
        ),
      );
      if (_disposed || session != _session) {
        await candidate.disconnect();
        return;
      }
      _device = candidate;
      await _connectionSubscription?.cancel();
      _connectionSubscription = candidate.connectionStream.listen((
        isConnected,
      ) {
        if (!isConnected && session == _session) _onDisconnected();
      });
      await _bindCharacteristics(candidate);
      if (_disposed || session != _session) {
        await candidate.disconnect();
        return;
      }
      linkState = HelmetLinkState.connected;
      message = null;
      _notify();
    } catch (error) {
      if (session == _session) {
        ++_session;
        _clearConnection();
        final unsupported = error is UnsupportedError;
        if (unsupported) _wantedDevice = null;
        linkState = unsupported
            ? HelmetLinkState.disconnected
            : HelmetLinkState.reconnecting;
        _setMessage(error);
        try {
          await candidate.disconnect();
        } catch (_) {
          // A failed connection may have nothing left to disconnect.
        }
        if (!unsupported) _scheduleReconnect();
      }
    } finally {
      _connecting = false;
    }
  }

  Future<void> _bindCharacteristics(BleDevice device) async {
    final services = await device.discoverServices();
    if (!services.any(
      (service) =>
          HelmetUuid.matches(service.uuid, HelmetUuid.telemetryService),
    )) {
      throw UnsupportedError(
        'This device does not expose the Smart Helmet service.',
      );
    }

    Future<BleCharacteristic> chr(String service, String characteristic) =>
        device.getCharacteristic(characteristic, service: service);

    _telemetryChar = await chr(
      HelmetUuid.telemetryService,
      HelmetUuid.telemetry,
    );
    _alertChar = await chr(HelmetUuid.telemetryService, HelmetUuid.alert);
    _configChar = await chr(HelmetUuid.configService, HelmetUuid.config);
    _configResultChar = await chr(
      HelmetUuid.configService,
      HelmetUuid.configResult,
    );
    _otaControlChar = await chr(HelmetUuid.otaService, HelmetUuid.otaControl);
    _otaDataChar = await chr(HelmetUuid.otaService, HelmetUuid.otaData);
    _otaStatusChar = await chr(HelmetUuid.otaService, HelmetUuid.otaStatus);
    _fileControlChar = await chr(
      HelmetUuid.fileService,
      HelmetUuid.fileControl,
    );
    _fileDataChar = await chr(HelmetUuid.fileService, HelmetUuid.fileData);
    _fileStatusChar = await chr(HelmetUuid.fileService, HelmetUuid.fileStatus);

    // An encrypted read triggers the platform's bonding flow when needed.
    config = HelmetConfig.parse(await _configChar!.read());
    telemetry = HelmetTelemetry.parse(await _telemetryChar!.read());

    _characteristicSubscriptions.addAll([
      _telemetryChar!.onValueReceived.listen((bytes) {
        try {
          telemetry = HelmetTelemetry.parse(bytes);
          packetsReceived++;
          _notify();
        } catch (error) {
          _setMessage(error);
        }
      }),
      _alertChar!.onValueReceived.listen((bytes) {
        try {
          alerts.insert(0, HelmetAlert.parse(bytes));
          if (alerts.length > 100) alerts.removeLast();
          _notify();
        } catch (error) {
          _setMessage(error);
        }
      }),
      _configResultChar!.onValueReceived.listen((bytes) {
        if (bytes.length == 3 &&
            bytes[0] == 0x80 &&
            bytes[1] == _pendingConfigCommand &&
            _configResult?.isCompleted == false) {
          _configResult!.complete(bytes[2]);
        }
      }),
      _otaStatusChar!.onValueReceived.listen((bytes) {
        try {
          otaStatus = HelmetTransferStatus.parse(bytes);
          _notify();
        } catch (error) {
          _setMessage(error);
        }
      }),
      _fileStatusChar!.onValueReceived.listen((bytes) {
        try {
          fileStatus = HelmetTransferStatus.parse(bytes);
          _notify();
        } catch (error) {
          _setMessage(error);
        }
      }),
    ]);

    await _telemetryChar!.notifications.subscribe();
    await _alertChar!.notifications.subscribe();
    await _configResultChar!.notifications.subscribe();
    await _otaStatusChar!.notifications.subscribe();
    await _fileStatusChar!.notifications.subscribe();
    otaStatus = HelmetTransferStatus.parse(await _otaStatusChar!.read());
    fileStatus = HelmetTransferStatus.parse(await _fileStatusChar!.read());
    try {
      negotiatedMtu = await device.requestMtu(247);
    } catch (_) {
      negotiatedMtu = 23;
    }
  }

  void _onDisconnected() {
    _session++;
    _clearConnection();
    if (_wantedDevice == null) {
      linkState = HelmetLinkState.disconnected;
    } else {
      linkState = HelmetLinkState.reconnecting;
      _scheduleReconnect();
    }
    _notify();
  }

  void _scheduleReconnect() {
    if (_wantedDevice == null || _disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      const Duration(seconds: 4),
      () => unawaited(_connectWanted()),
    );
  }

  void _clearConnection() {
    for (final subscription in _characteristicSubscriptions) {
      unawaited(subscription.cancel());
    }
    _characteristicSubscriptions.clear();
    unawaited(_connectionSubscription?.cancel() ?? Future<void>.value());
    _connectionSubscription = null;
    _device = null;
    _telemetryChar = null;
    _alertChar = null;
    _configChar = null;
    _configResultChar = null;
    _otaControlChar = null;
    _otaDataChar = null;
    _otaStatusChar = null;
    _fileControlChar = null;
    _fileDataChar = null;
    _fileStatusChar = null;
    _configResult = null;
    _pendingConfigCommand = null;
    _abortTransfer = true;
    activeTransfer = null;
    config = null;
    otaStatus = null;
    fileStatus = null;
    negotiatedMtu = null;
  }

  Future<void> disconnect() async {
    _wantedDevice = null;
    _reconnectTimer?.cancel();
    ++_session;
    final device = _device;
    _clearConnection();
    linkState = HelmetLinkState.disconnected;
    _notify();
    if (device != null) {
      try {
        await device.disconnect();
      } catch (error) {
        _setMessage(error);
      }
    }
  }

  Future<void> _sendConfig(int command, List<int> bytes) async {
    final characteristic = _configChar;
    if (!connected || characteristic == null) {
      throw StateError('Connect to the Helmet first.');
    }
    if (_configResult != null) {
      throw StateError('Another setting is still being saved.');
    }
    final completer = Completer<int>();
    _configResult = completer;
    _pendingConfigCommand = command;
    try {
      await characteristic.write(bytes);
      final result = await completer.future.timeout(
        const Duration(seconds: 10),
      );
      if (result != 0) throw StateError('The Helmet rejected this setting.');
      config = HelmetConfig.parse(await characteristic.read());
      _notify();
    } finally {
      if (identical(_configResult, completer)) {
        _configResult = null;
        _pendingConfigCommand = null;
      }
    }
  }

  Future<void> setInterval(int milliseconds) async {
    if (milliseconds < 100 || milliseconds > 60000) {
      throw ArgumentError.value(
        milliseconds,
        'milliseconds',
        'Must be 100–60000',
      );
    }
    await _sendConfig(1, [1, milliseconds & 0xff, milliseconds >> 8]);
  }

  Future<void> setAlertsEnabled(bool enabled) =>
      _sendConfig(2, [2, enabled ? 1 : 0]);

  Future<void> setDeviceName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed.length > 20 ||
        !RegExp(r'^[\x20-\x7E]+$').hasMatch(trimmed)) {
      throw const FormatException('Use 1–20 printable English characters.');
    }
    await _sendConfig(3, [3, ...trimmed.codeUnits]);
  }

  Future<void> resetSettings() => _sendConfig(4, [4]);

  Future<void> refresh() async {
    if (!connected) return;
    config = HelmetConfig.parse(await _configChar!.read());
    telemetry = HelmetTelemetry.parse(await _telemetryChar!.read());
    otaStatus = HelmetTransferStatus.parse(await _otaStatusChar!.read());
    fileStatus = HelmetTransferStatus.parse(await _fileStatusChar!.read());
    _notify();
  }

  void clearAlerts() {
    alerts.clear();
    _notify();
  }

  HelmetTransferStatus? statusFor(TransferKind kind) =>
      kind == TransferKind.firmware ? otaStatus : fileStatus;

  Future<HelmetTransferStatus> _readTransferStatus(TransferKind kind) async {
    final characteristic = kind == TransferKind.firmware
        ? _otaStatusChar
        : _fileStatusChar;
    if (characteristic == null) throw StateError('The Helmet disconnected.');
    final status = HelmetTransferStatus.parse(await characteristic.read());
    if (kind == TransferKind.firmware) {
      otaStatus = status;
    } else {
      fileStatus = status;
    }
    _notify();
    return status;
  }

  Future<HelmetTransferStatus> _waitForStatus(
    TransferKind kind,
    bool Function(HelmetTransferStatus) done, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final until = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(until)) {
      if (!connected || _abortTransfer) throw StateError('Transfer stopped.');
      final status = await _readTransferStatus(kind);
      if (status.state == TransferState.failed) {
        throw StateError('Helmet reported transfer failure.');
      }
      if (done(status)) return status;
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
    throw TimeoutException('The Helmet did not acknowledge the transfer.');
  }

  Future<void> sendFile(
    Uint8List bytes,
    String name,
    TransferKind kind, {
    int fileType = 1,
  }) async {
    if (!connected) throw StateError('Connect to the Helmet first.');
    if (transferring) throw StateError('A transfer is already running.');
    if (bytes.isEmpty || bytes.length > 0x140000) {
      throw StateError('Select a nonempty file no larger than 1.25 MiB.');
    }
    if (kind == TransferKind.file && (fileType < 1 || fileType > 255)) {
      throw StateError('File type must be between 1 and 255.');
    }
    final control = kind == TransferKind.firmware
        ? _otaControlChar
        : _fileControlChar;
    final data = kind == TransferKind.firmware ? _otaDataChar : _fileDataChar;
    if (control == null || data == null) {
      throw StateError('Transfer service is unavailable.');
    }
    final previous = await _readTransferStatus(kind);
    if (previous.state == TransferState.receiving ||
        previous.state == TransferState.verifying) {
      throw StateError('The Helmet is already receiving a transfer.');
    }
    activeTransfer = kind;
    transferFileName = name;
    _abortTransfer = false;
    _notify();
    try {
      final digest = sha256.convert(bytes).bytes;
      final start = [
        1,
        if (kind == TransferKind.file) fileType,
        ...u32Bytes(bytes.length),
        ...digest,
      ];
      await control.write(start);
      await _waitForStatus(
        kind,
        (s) =>
            s.state == TransferState.receiving && s.totalSize == bytes.length,
      );

      // The firmware queue holds eight chunks. Limit each batch to four and
      // wait for bytes_received before sending the next one.
      final chunkSize = ((negotiatedMtu ?? 23) - 3).clamp(20, 240);
      var offset = 0;
      while (offset < bytes.length) {
        for (var sent = 0; sent < 4 && offset < bytes.length; sent++) {
          if (_abortTransfer || !connected) {
            throw StateError('Transfer stopped.');
          }
          final end = (offset + chunkSize).clamp(0, bytes.length);
          await data.write(bytes.sublist(offset, end), withResponse: false);
          offset = end;
        }
        final expected = offset;
        await _waitForStatus(kind, (s) => s.bytesReceived >= expected);
      }
      await control.write([2]);
      await _waitForStatus(kind, (s) => s.state == TransferState.completed);
    } catch (error) {
      if (connected) {
        try {
          await control.write([3]);
        } catch (_) {}
      }
      rethrow;
    } finally {
      activeTransfer = null;
      transferFileName = null;
      _abortTransfer = false;
      _notify();
    }
  }

  Future<void> abortTransfer() async {
    final kind = activeTransfer;
    if (kind == null) return;
    _abortTransfer = true;
    _notify();
  }

  Future<void> rebootUpdatedFirmware() async {
    if (!connected || otaStatus?.state != TransferState.completed) {
      throw StateError('Complete and verify a firmware transfer first.');
    }
    await _otaControlChar!.write([4]);
  }

  @override
  void dispose() {
    _disposed = true;
    _scanTimer?.cancel();
    _reconnectTimer?.cancel();
    unawaited(_scanSubscription?.cancel() ?? Future<void>.value());
    unawaited(_availabilitySubscription?.cancel() ?? Future<void>.value());
    _clearConnection();
    super.dispose();
  }
}
