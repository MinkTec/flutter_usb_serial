/// Flutter plugin for USB serial (COM port) communication on Android.
///
/// Basic usage:
/// ```dart
/// // 1. List connected devices
/// final devices = await FlutterUsbSerial.getDevices();
///
/// // 2. Request USB permission if needed
/// if (!devices[0].hasPermission) {
///   await FlutterUsbSerial.requestPermission(devices[0]);
/// }
///
/// // 3. Open a port
/// final port = await FlutterUsbSerial.openPort(devices[0], baudRate: 115200);
///
/// // 4. Subscribe to incoming data
/// port?.inputStream.listen((bytes) { /* handle Uint8List */ });
///
/// // 5. Send data
/// await port?.write(Uint8List.fromList('hello\r\n'.codeUnits));
///
/// // 6. Close when done
/// await port?.close();
/// ```
library flutter_usb_serial;

import 'package:flutter/services.dart';

import 'src/usb_device.dart';
import 'src/usb_params.dart';
import 'src/usb_port.dart';

export 'src/usb_device.dart';
export 'src/usb_params.dart';
export 'src/usb_port.dart';

/// Main entry point for the flutter_usb_serial plugin.
class FlutterUsbSerial {
  FlutterUsbSerial._();

  static const _ch = MethodChannel('flutter_usb_serial');

  // ── Device enumeration ──────────────────────────────────────────────────

  /// Returns all currently connected USB serial devices.
  ///
  /// Does **not** require USB permission — metadata (VID, PID, driver type)
  /// is always readable. The [UsbDevice.hasPermission] field indicates
  /// whether the app can open that device right now.
  static Future<List<UsbDevice>> getDevices() async {
    final raw = await _ch.invokeListMethod<Object?>('getDevices');
    if (raw == null) return [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(UsbDevice.fromMap)
        .toList();
  }

  // ── Permissions ─────────────────────────────────────────────────────────

  /// Returns `true` if the app already holds USB permission for [device].
  static Future<bool> hasPermission(UsbDevice device) async {
    return (await _ch.invokeMethod<bool>(
          'hasPermission',
          {'deviceId': device.deviceId},
        )) ??
        false;
  }

  /// Asks the user to grant USB permission for [device].
  ///
  /// Shows the system permission dialog if needed and returns `true` if the
  /// user granted access. Returns `true` immediately if the app already has
  /// permission (no dialog is shown).
  static Future<bool> requestPermission(UsbDevice device) async {
    return (await _ch.invokeMethod<bool>(
          'requestPermission',
          {'deviceId': device.deviceId},
        )) ??
        false;
  }

  // ── Port management ──────────────────────────────────────────────────────

  /// Opens [portNumber] on [device] and configures the UART parameters.
  ///
  /// The device must already have USB permission — call [requestPermission]
  /// first if [UsbDevice.hasPermission] is `false`.
  ///
  /// Returns a [UsbPort] handle on success, or throws [PlatformException]
  /// on failure (permission denied, no matching driver, device busy, etc.).
  static Future<UsbPort> openPort(
    UsbDevice device, {
    int portNumber = 0,
    int baudRate = 9600,
    int dataBits = UsbDataBits.bits8,
    int stopBits = UsbStopBits.one,
    int parity = UsbParity.none,
  }) async {
    final portId = await _ch.invokeMethod<int>('openPort', {
      'deviceId': device.deviceId,
      'portNumber': portNumber,
      'baudRate': baudRate,
      'dataBits': dataBits,
      'stopBits': stopBits,
      'parity': parity,
    });
    if (portId == null) {
      throw PlatformException(
        code: 'OPEN_FAILED',
        message: 'openPort returned null portId',
      );
    }
    return UsbPort.fromPortId(portId);
  }
}
