import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// The UUIDs and binary layouts are shared with docs/ble-protocol.md.
abstract final class HelmetUuid {
  static const telemetryService = 'FFF0';
  static const telemetry = 'FFF1';
  static const alert = 'FFF2';
  static const configService = 'FFF3';
  static const config = 'FFF4';
  static const configResult = 'FFF5';
  static const otaService = 'FFF6';
  static const otaControl = 'FFF7';
  static const otaData = 'FFF8';
  static const otaStatus = 'FFF9';
  static const fileService = 'FFFA';
  static const fileControl = 'FFFB';
  static const fileData = 'FFFC';
  static const fileStatus = 'FFFD';

  static bool matches(String actual, String expected) =>
      BleUuidParser.compareStrings(actual, expected);
}

String hexBytes(List<int> bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

int _u16(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint16(at, Endian.little);
int _u32(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint32(at, Endian.little);

Uint8List u32Bytes(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

class HelmetTelemetry {
  const HelmetTelemetry({
    required this.version,
    required this.flags,
    required this.sequence,
    required this.timestampMs,
    required this.payload,
    required this.receivedAt,
  });

  final int version;
  final int flags;
  final int sequence;
  final int timestampMs;
  final Uint8List payload;
  final DateTime receivedAt;

  static HelmetTelemetry parse(Uint8List bytes) {
    if (bytes.length < 9 || bytes[8] > 64 || bytes.length != 9 + bytes[8]) {
      throw const FormatException('Invalid telemetry packet length');
    }
    return HelmetTelemetry(
      version: bytes[0],
      flags: bytes[1],
      sequence: _u16(bytes, 2),
      timestampMs: _u32(bytes, 4),
      payload: Uint8List.sublistView(bytes, 9),
      receivedAt: DateTime.now(),
    );
  }
}

class HelmetAlert {
  const HelmetAlert({
    required this.code,
    required this.severity,
    required this.sequence,
    required this.timestampMs,
    required this.payload,
    required this.receivedAt,
  });

  final int code;
  final int severity;
  final int sequence;
  final int timestampMs;
  final Uint8List payload;
  final DateTime receivedAt;

  String get severityLabel => switch (severity) {
    1 => 'Info',
    2 => 'Warning',
    3 => 'Critical',
    _ => 'Level $severity',
  };

  static HelmetAlert parse(Uint8List bytes) {
    if (bytes.length < 9 || bytes[8] > 32 || bytes.length != 9 + bytes[8]) {
      throw const FormatException('Invalid alert packet length');
    }
    return HelmetAlert(
      code: bytes[0],
      severity: bytes[1],
      sequence: _u16(bytes, 2),
      timestampMs: _u32(bytes, 4),
      payload: Uint8List.sublistView(bytes, 9),
      receivedAt: DateTime.now(),
    );
  }
}

class HelmetConfig {
  const HelmetConfig({
    required this.version,
    required this.intervalMs,
    required this.alertsEnabled,
    required this.deviceName,
  });

  final int version;
  final int intervalMs;
  final bool alertsEnabled;
  final String deviceName;

  static HelmetConfig parse(Uint8List bytes) {
    if (bytes.length < 5 || bytes[4] > 20 || bytes.length != 5 + bytes[4]) {
      throw const FormatException('Invalid configuration packet length');
    }
    return HelmetConfig(
      version: bytes[0],
      intervalMs: _u16(bytes, 1),
      alertsEnabled: bytes[3] != 0,
      deviceName: ascii.decode(bytes.sublist(5)),
    );
  }
}

enum TransferState { idle, receiving, verifying, completed, failed }

class HelmetTransferStatus {
  const HelmetTransferStatus({
    required this.state,
    required this.progress,
    required this.bytesReceived,
    required this.totalSize,
  });

  final TransferState state;
  final int progress;
  final int bytesReceived;
  final int totalSize;

  static HelmetTransferStatus parse(Uint8List bytes) {
    if (bytes.length != 10 || bytes[0] >= TransferState.values.length) {
      throw const FormatException('Invalid transfer status packet');
    }
    return HelmetTransferStatus(
      state: TransferState.values[bytes[0]],
      progress: bytes[1].clamp(0, 100),
      bytesReceived: _u32(bytes, 2),
      totalSize: _u32(bytes, 6),
    );
  }
}
